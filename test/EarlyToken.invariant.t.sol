// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {EarlyToken} from "../src/EarlyToken.sol";

/// @dev Test-only state machine with an independent ledger for four participants.
contract TokenHandler is Test {
    EarlyToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(EarlyToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = token_.totalSupply();
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount, bool invalid) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 balance = expectedBalance[from];
        amount = invalid ? bound(amount, balance + 1, type(uint256).max) : bound(amount, 0, balance);

        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        if (invalid) {
            assertFalse(success, "overspending succeeded");
            assertEq(
                result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        } else {
            assertTrue(success, "valid transfer reverted");
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        // Approval is not capped by the holder's balance or by the token supply.
        amount = unlimited ? type(uint256).max : bound(amount, 0, type(uint256).max - 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount, bool invalid) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        uint256 balance = expectedBalance[owner];
        uint256 allowance_ = expectedAllowance[owner][spender];
        uint256 available = balance < allowance_ ? balance : allowance_;
        amount = invalid ? bound(amount, available + 1, type(uint256).max) : bound(amount, 0, available);

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        if (invalid) {
            assertFalse(success, "invalid delegated transfer succeeded");
            bytes memory expectedError = amount > allowance_
                ? abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance_, amount)
                : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount);
            assertEq(result, expectedError);
        } else {
            assertTrue(success, "valid delegated transfer reverted");
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[owner] -= amount;
            expectedBalance[to] += amount;
            if (allowance_ != type(uint256).max) {
                expectedAllowance[owner][spender] -= amount;
            }
        }
    }

    function revoke(uint8 ownerSeed, uint8 spenderSeed) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function rejectZeroSpender(uint8 ownerSeed, uint256 amount) external {
        _expectFailure(
            actors[ownerSeed % 4],
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function rejectZeroRecipient(uint8 ownerSeed, uint8 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 available = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < available) {
            available = expectedAllowance[owner][spender];
        }
        // Satisfy balance/allowance checks so the invalid recipient is actually reached.
        amount = bound(amount, 0, available);
        bytes memory data = delegated
            ? abi.encodeCall(token.transferFrom, (owner, address(0), amount))
            : abi.encodeCall(token.transfer, (address(0), amount));
        _expectFailure(
            delegated ? spender : owner,
            data,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    /// @dev No ghost updates on failure: the next invariant checks every balance and allowance for rollback.
    function _expectFailure(address caller, bytes memory data, bytes memory expectedError) internal {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(result, expectedError, "unexpected revert reason");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract EarlyTokenInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    EarlyToken internal token;
    TokenHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        token = new EarlyToken();
        actors = [makeAddr("actor-0"), makeAddr("actor-1"), makeAddr("actor-2"), makeAddr("actor-3")];
        token.transfer(actors[0], SUPPLY);
        handler = new TokenHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.revoke.selector;
        selectors[4] = TokenHandler.rejectZeroSpender.selector;
        selectors[5] = TokenHandler.rejectZeroRecipient.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyIsFixedAndAllTokensAreAccountedFor() public view {
        uint256 held;
        for (uint256 i; i < actors.length; ++i) {
            held += token.balanceOf(actors[i]);
        }
        assertEq(held, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_balancesAndAllowancesMatchIndependentLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]));
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}

