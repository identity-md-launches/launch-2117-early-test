// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {EarlyToken} from "../src/EarlyToken.sol";

/// @dev Test-only factory: demonstrates the same constructor caller semantics as CREATE2 launch.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (EarlyToken) {
        return new EarlyToken{salt: salt}();
    }
}

contract EarlyTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    EarlyToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new EarlyToken();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "EARLY TEST");
        assertEq(token.symbol(), "EARLY");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.TELEGRAM_URL(), "https://t.me/EARLYCATODAY");
    }

    function test_constructorMintsOnceAndEmitsOneTransfer() public {
        vm.recordLogs();
        vm.prank(alice);
        EarlyToken deployed = new EarlyToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_create2MintsToFactoryAndNotItsCaller() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        vm.prank(alice, alice);
        EarlyToken deployed = factory.deploy(keccak256("EARLY launch"));

        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 25e18);
        assertTrue(token.transfer(alice, 25e18));
        assertEq(token.balanceOf(alice), 25e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 25e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireBalance() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferRejectsInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferStillRequiresBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
    }

    function test_transferRejectsZeroRecipientIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsEventWithoutMovingBalances() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 50e18);
        assertTrue(token.approve(spender, 50e18));
        assertEq(token.allowance(address(this), spender), 50e18);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_approvalCanBeReplacedAndRevoked() public {
        token.approve(spender, 50e18);
        token.approve(spender, 20e18);
        assertEq(token.allowance(address(this), spender), 20e18);
        token.approve(spender, 0);
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approveRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_transferFromDeliversExactAmountAndConsumesAllowance() public {
        token.approve(spender, 50e18);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 20e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 20e18));
        assertEq(token.allowance(address(this), spender), 30e18);
        assertEq(token.balanceOf(alice), 20e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20e18);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 30e18));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 30e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromSelfConsumesAllowanceWithoutChangingBalance() public {
        token.approve(spender, 10e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 10e18));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_infiniteAllowanceIsNotConsumed() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 10e18));
        assertTrue(token.transferFrom(address(this), bob, 20e18));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 10e18);
        assertEq(token.balanceOf(bob), 20e18);
    }

    function test_transferFromZeroAmountNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromRejectsInsufficientAllowanceWithoutChangingState() public {
        token.approve(spender, 10e18);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10e18, 10e18 + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 10e18 + 1);
        assertEq(token.allowance(address(this), spender), 10e18);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferFromRejectsInsufficientBalanceAndRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10e18));
        vm.prank(spender);
        token.transferFrom(alice, bob, 10e18);
        assertEq(token.allowance(alice, spender), 10e18);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromRejectsZeroRecipientAndRestoresAllowance() public {
        token.approve(spender, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10e18);
        assertEq(token.allowance(address(this), spender), 10e18);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromRejectsZeroSenderEvenForZeroAmount() public {
        // OpenZeppelin validates the allowance owner before checking the transfer sender.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_deployerCannotSpendHolderTokensWithoutApproval() public {
        token.transfer(alice, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 10e18);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10e18));
        assertEq(token.balanceOf(bob), 10e18);
    }

    function test_noMintBurnOrAdministrativeEntrypoints() public {
        token.transfer(alice, 10e18);
        bytes[] memory calls = new bytes[](17);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("unpause()");
        calls[7] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[8] = abi.encodeWithSignature("freeze(address)", alice);
        calls[9] = abi.encodeWithSignature("seize(address)", alice);
        calls[10] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[11] = abi.encodeWithSignature("initialize(address)", bob);
        calls[12] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[13] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[14] = abi.encodeWithSignature("setOwner(address)", bob);
        calls[15] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        calls[16] = abi.encodeWithSignature("setTelegramUrl(string)", "https://example.invalid");

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess, "deployer reached an unintended entry point");
            vm.prank(bob);
            (bool strangerSuccess,) = address(token).call(calls[i]);
            assertFalse(strangerSuccess, "stranger reached an unintended entry point");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10e18);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10e18));
        assertEq(token.balanceOf(bob), 10e18);
    }

    function test_plainEtherTransferReverts() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeFitsDeploymentLimitAndHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden opcode");
        }
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferOverBalanceReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromTracksRemainingAllowance(uint256 allowance_, uint256 amount) public {
        allowance_ = bound(allowance_, 0, SUPPLY);
        amount = bound(amount, 0, allowance_);
        token.approve(spender, allowance_);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), allowance_ - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
