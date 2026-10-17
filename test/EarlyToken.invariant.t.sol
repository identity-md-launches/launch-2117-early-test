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
        amount = invalid ? balance + 1 : bound(amount, 0, balance);

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
        amount = unlimited ? type(uint256).max : bound(amount, 0, token.INITIAL_SUPPLY());
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
        amount = invalid ? available + 1 : bound(amount, 0, available);

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
}

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

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
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
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}

