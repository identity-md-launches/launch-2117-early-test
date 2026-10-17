// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {EarlyToken} from "src/EarlyToken.sol";

/// @dev Extends the existing suite with arithmetic edges, caller separation and recovery after failures.
/// forge-config: default.fuzz.runs = 1000
contract EarlyTokenBoundariesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000e18;
    EarlyToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;
    address internal otherSpender;

    function setUp() public {
        token = new EarlyToken();
        alice = makeAddr("boundary-alice");
        bob = makeAddr("boundary-bob");
        spender = makeAddr("boundary-spender");
        otherSpender = makeAddr("boundary-other-spender");
    }

    function test_roundTripAtZeroOneWeiAndSupplyEdges() public {
        _roundTrip(0);
        _roundTrip(1);
        _roundTrip(SUPPLY - 1);
        _roundTrip(SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresEveryBalance(uint256 amount) public {
        _roundTrip(bound(amount, 0, SUPPLY));
    }

    function test_largestFiniteApprovalIsConsumed() public {
        _spendFiniteApproval(type(uint256).max - 1, 1);
    }

    function testFuzz_finiteApprovalsAboveSupplyStillDecrease(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, type(uint256).max - 1);
        amount = bound(amount, 0, approval < SUPPLY ? approval : SUPPLY);
        _spendFiniteApproval(approval, amount);
    }

    function test_maximumTransferCannotWrapBalancesOrUseInfiniteApprovalToMint() public {
        uint256 amount = type(uint256).max;
        bytes memory insufficientBalance =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount);
        vm.expectRevert(insufficientBalance);
        token.transfer(alice, amount);
        _assertBalances(SUPPLY, 0, 0);

        assertTrue(token.approve(spender, amount));
        vm.expectRevert(insufficientBalance);
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), amount);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_insufficientBalanceRestoresApprovalAndCanBeRetried(
        uint256 balance,
        uint256 amount,
        bool unlimited
    ) public {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        uint256 approval = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approval));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approval);
        _assertBalances(SUPPLY - balance, balance, 0);

        // The same authorization must remain usable after the holder obtains enough tokens.
        assertTrue(token.transfer(alice, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), unlimited ? approval : 0);
        _assertBalances(SUPPLY - amount, 0, amount);
    }

    function testFuzz_insufficientAllowanceIsAtomicAndCanBeRetried(uint256 approval, uint256 amount) public {
        approval = bound(approval, 0, SUPPLY - 1);
        amount = bound(amount, approval + 1, SUPPLY);
        assertTrue(token.approve(spender, approval));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approval);
        _assertBalances(SUPPLY, 0, 0);

        assertTrue(token.approve(spender, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - amount, amount, 0);
    }

    function test_zeroRecipientRejectsZeroAmountWithFiniteAndInfiniteApproval() public {
        _rejectZeroRecipientThenRetry(0, 0);
        _rejectZeroRecipientThenRetry(type(uint256).max, 0);
    }

    function testFuzz_zeroRecipientRestoresApprovalAndCanBeRetried(uint256 approval, uint256 amount, bool unlimited)
        public
    {
        approval = unlimited ? type(uint256).max : bound(approval, 0, type(uint256).max - 1);
        amount = bound(amount, 0, approval < SUPPLY ? approval : SUPPLY);
        _rejectZeroRecipientThenRetry(approval, amount);
    }

    function test_zeroSpenderRejectsZeroAndMaximumApprovalWithoutTouchingOtherApprovals() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_transferFromByHolderStillNeedsSelfApproval() public {
        bytes memory noApproval =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1);
        vm.expectRevert(noApproval);
        token.transferFrom(address(this), alice, 1);
        _assertBalances(SUPPLY, 0, 0);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), address(this), 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        _assertBalances(SUPPLY, 0, 0);

        vm.expectRevert(noApproval);
        token.transferFrom(address(this), alice, 1);
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function testFuzz_delegationUsesCallerNotTransactionOrigin(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, amount));
        vm.prank(bob, alice);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.allowance(alice, bob), 0);
        _assertBalances(SUPPLY - amount, amount, 0);

        vm.prank(spender, bob);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY - amount, 0, amount);
    }

    function testFuzz_approvalsAreIsolatedByBothOwnerAndSpender(
        uint256 aliceApproval,
        uint256 otherSpenderApproval,
        uint256 bobApproval,
        uint256 amount
    ) public {
        assertTrue(token.transfer(alice, SUPPLY / 2));
        assertTrue(token.transfer(bob, SUPPLY / 2));
        vm.startPrank(alice);
        assertTrue(token.approve(spender, aliceApproval));
        assertTrue(token.approve(otherSpender, otherSpenderApproval));
        vm.stopPrank();
        vm.prank(bob);
        assertTrue(token.approve(spender, bobApproval));
        _assertBalances(0, SUPPLY / 2, SUPPLY / 2);

        amount = bound(amount, 0, aliceApproval < SUPPLY / 2 ? aliceApproval : SUPPLY / 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        uint256 remaining = aliceApproval == type(uint256).max ? aliceApproval : aliceApproval - amount;
        assertEq(token.allowance(alice, spender), remaining);
        assertEq(token.allowance(alice, otherSpender), otherSpenderApproval);
        assertEq(token.allowance(bob, spender), bobApproval);
        assertEq(token.allowance(bob, otherSpender), 0);
        assertEq(token.allowance(spender, alice), 0);
        _assertBalances(0, SUPPLY / 2 - amount, SUPPLY / 2 + amount);
    }

    function test_infiniteApprovalCanBeReducedThenRevokedAfterSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 2);
        assertEq(token.allowance(address(this), spender), 1);
        _assertBalances(SUPPLY - 1, 1, 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - 2, 2, 0);
    }

    function testFuzz_selfTransferFromPreservesBalanceButConsumesFiniteApproval(
        uint256 balance,
        uint256 approval,
        uint256 amount,
        bool holderIsSpender
    ) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, 0, approval < balance ? approval : balance);
        address caller = holderIsSpender ? alice : spender;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(caller, approval));
        vm.prank(caller);
        assertTrue(token.transferFrom(alice, alice, amount));
        assertEq(token.allowance(alice, caller), approval == type(uint256).max ? approval : approval - amount);
        _assertBalances(SUPPLY - balance, balance, 0);
    }

    function _roundTrip(uint256 amount) internal {
        assertTrue(token.transfer(alice, amount));
        _assertBalances(SUPPLY - amount, amount, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        _assertBalances(SUPPLY - amount, 0, amount);
        vm.prank(bob);
        assertTrue(token.transfer(address(this), amount));
        _assertBalances(SUPPLY, 0, 0);
    }

    function _spendFiniteApproval(uint256 approval, uint256 amount) internal {
        assertTrue(token.approve(spender, approval));
        assertEq(token.allowance(address(this), spender), approval);
        _assertBalances(SUPPLY, 0, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approval - amount);
        _assertBalances(SUPPLY - amount, amount, 0);
    }

    function _rejectZeroRecipientThenRetry(uint256 approval, uint256 amount) internal {
        assertTrue(token.approve(spender, approval));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approval);
        _assertBalances(SUPPLY, 0, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approval == type(uint256).max ? approval : approval - amount);
        _assertBalances(SUPPLY - amount, amount, 0);
    }

    function _assertBalances(uint256 deployerBalance, uint256 aliceBalance, uint256 bobBalance) internal view {
        assertEq(token.balanceOf(address(this)), deployerBalance);
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
