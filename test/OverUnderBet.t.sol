// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../src/OverUnderBet.sol";

/**
 * @notice A simple mock aggregator that lets you set the price manually.
 */
contract MockAggregator {
    int256 private _price;
    uint80 private _roundId;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;

    constructor(int256 initialPrice) {
        _price = initialPrice;
        _roundId = 1;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
        _answeredInRound = 1;
    }

    /// @notice Let you update the price.
    function setPrice(int256 newPrice) public {
        _price = newPrice;
        _updatedAt = block.timestamp;
        _roundId += 1;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (_roundId, _price, _startedAt, _updatedAt, _answeredInRound);
    }
}

contract OverUnderBetTest is Test {
    OverUnderBet betContract;
    MockAggregator aggregator;
    uint256 betDate;

    address bettorOver = address(1);
    address bettorUnder = address(2);

    function setUp() public {
        aggregator = new MockAggregator(2000 * 1e8);

        betDate = block.timestamp + 10 minutes;

        betContract = new OverUnderBet(address(aggregator), betDate);

        vm.deal(bettorOver, 10 ether);
        vm.deal(bettorUnder, 10 ether);
    }

    function testBetUnderUpdatesState() public {
        uint256 betAmount = 1 ether;

        betContract.betUnder{value: betAmount}();

        assertEq(betContract.totalUnder(), betAmount);

        assertEq(betContract.bettingUnder(0), address(this));
    }

    function testBetOverUpdatesState() public {
        uint256 betAmount = 1 ether;

        vm.prank(bettorOver);
        betContract.betOver{value: betAmount}();

        assertEq(betContract.totalOver(), betAmount);

        assertEq(betContract.bettingOver(0), bettorOver);
    }

    function testBettingWindowClosed() public {
        // Warp time to just after the closing betting window.
        vm.warp(betContract.closingBookTimestamp() + 1);

        // Trying to place a bet now should revert.
        vm.expectRevert("Betting window closed");
        betContract.betUnder{value: 1 ether}();
    }

    function testPayBetsOverWins() public {
        uint256 betAmount = 1 ether;

        vm.deal(bettorOver, 10 ether);
        vm.deal(bettorUnder, 10 ether);

        vm.warp(betContract.openingBookTimestamp() + 1);

        // BettorOver places an "over" bet.
        vm.prank(bettorOver);
        betContract.betOver{value: betAmount}();

        // BettorUnder places an "under" bet.
        vm.prank(bettorUnder);
        betContract.betUnder{value: betAmount}();

        assertEq(address(betContract).balance, 2 ether);

        // Warp to after the bet date.
        vm.warp(betDate + 1);

        // Update the aggregator price so that "over" wins.
        aggregator.setPrice(3000 * 1e8);

        uint256 balanceOverBefore = bettorOver.balance;
        uint256 balanceUnderBefore = bettorUnder.balance;

        betContract.payBets();

        assertEq(address(betContract).balance, 0);

        uint256 expectedPayout = 2 ether;

        // Check that bettorOver’s balance increased by the expected payout.
        uint256 balanceOverAfter = bettorOver.balance;
        assertEq(balanceOverAfter, balanceOverBefore + expectedPayout);

        // The losing side doesn't receive a refund when there is at least one winning bet,
        // bettorUnder’s balance should remain unchanged (apart from their earlier bet deduction).
        uint256 balanceUnderAfter = bettorUnder.balance;
        assertEq(balanceUnderAfter, balanceUnderBefore);
    }

    function testPayBetsUnderWins() public {
        uint256 betAmount = 1 ether;

        vm.deal(bettorOver, 10 ether);
        vm.deal(bettorUnder, 10 ether);

        vm.warp(betContract.openingBookTimestamp() + 1);

        // BettorOver places an "over" bet.
        vm.prank(bettorOver);
        betContract.betOver{value: betAmount}();

        // BettorUnder places an "under" bet.
        vm.prank(bettorUnder);
        betContract.betUnder{value: betAmount}();

        assertEq(address(betContract).balance, 2 ether);

        // Warp to after the bet date.
        vm.warp(betDate + 1);

        // Update the aggregator price so that "under" wins.
        aggregator.setPrice(1500 * 1e8);

        // Record balances before payout.
        uint256 balanceOverBefore = bettorOver.balance;
        uint256 balanceUnderBefore = bettorUnder.balance;

        // Resolve the bets.
        betContract.payBets();

        assertEq(address(betContract).balance, 0);

        uint256 expectedPayout = 2 ether;
        uint256 balanceUnderAfter = bettorUnder.balance;
        assertEq(balanceUnderAfter, balanceUnderBefore + expectedPayout);

        uint256 balanceOverAfter = bettorOver.balance;
        assertEq(balanceOverAfter, balanceOverBefore);
    }
}
