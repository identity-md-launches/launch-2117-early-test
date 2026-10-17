// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {EarlyToken} from "../src/EarlyToken.sol";

/// @dev Local stand-in for the factory's ERC-20 movements; not an implementation of the launch factory.
contract LaunchFlowFixture {
    function deployAndDistribute(address distributor, address pool, address recipient)
        external
        returns (EarlyToken token)
    {
        token = new EarlyToken{salt: keccak256("launch-flow")}();
        uint256 supply = token.totalSupply();
        require(token.balanceOf(address(this)) == supply, "factory did not receive supply");
        require(token.transfer(distributor, supply * 1_000 / 10_000), "swarm transfer failed");
        require(token.transfer(pool, supply * 8_800 / 10_000), "pool transfer failed");
        require(token.transfer(recipient, supply * 200 / 10_000), "remainder transfer failed");
    }
}

contract EarlyTokenLaunchTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    /// @dev Checks exact token movements. Actual pool initialization and swaps belong to the supplied launch harness.
    function test_launchDistributionClaimAndPoolTransfersArriveWhole() public {
        LaunchFlowFixture factory = new LaunchFlowFixture();
        address distributor = makeAddr("launch-distributor");
        address pool = makeAddr("launch-pool");
        address recipient = makeAddr("launch-recipient");
        address claimant = makeAddr("launch-claimant");
        address trader = makeAddr("launch-trader");
        EarlyToken token = factory.deployAndDistribute(distributor, pool, recipient);

        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), 100_000_000e18);
        assertEq(token.balanceOf(pool), 880_000_000e18);
        assertEq(token.balanceOf(recipient), 20_000_000e18);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, 100_000_000e18));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), 100_000_000e18);

        vm.prank(pool);
        assertTrue(token.transfer(trader, 123e18));
        assertEq(token.balanceOf(trader), 123e18);
        assertEq(token.balanceOf(pool), 880_000_000e18 - 123e18);
        vm.prank(trader);
        assertTrue(token.transfer(pool, 123e18));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), 880_000_000e18);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
