// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract OverUnderBet {
    uint256 public immutable openingBookTimestamp;
    uint256 public immutable closingBookTimestamp;
    uint256 public immutable betDate;
    int256 public immutable betOverUnderPrice;

    address[] public bettingOver;
    address[] public bettingUnder;

    mapping(address => uint256) betUnderAmounts;
    mapping(address => uint256) betOverAmounts;

    uint256 public totalOver;
    uint256 public totalUnder;

    bool public betsPaid;

    AggregatorV3Interface priceFeed;

    constructor(address _priceFeed, uint256 _betDate) {
        priceFeed = AggregatorV3Interface(_priceFeed);
        openingBookTimestamp = block.timestamp;
        closingBookTimestamp = block.timestamp + 5 minutes;
        betDate = _betDate;
        betOverUnderPrice = getLatestPrice();
    }

    function getLatestPrice() public view returns (int256) {
        (
            /*uint80 roundId*/
            ,
            int256 answer,
            /*uint256 startedAt*/
            ,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return answer;
    }

    function betUnder() public payable {
        require(
            block.timestamp >= openingBookTimestamp && block.timestamp <= closingBookTimestamp, "Betting window closed"
        );
        require(msg.value > 0, "Bet amount must be > 0");
        require(betOverAmounts[msg.sender] == 0, "Cannot bet on both over and under");

        if (betUnderAmounts[msg.sender] == 0) {
            bettingUnder.push(msg.sender);
        }
        betUnderAmounts[msg.sender] += msg.value;
        totalUnder += msg.value;
    }

    function betOver() public payable {
        require(
            block.timestamp >= openingBookTimestamp && block.timestamp <= closingBookTimestamp, "Betting window closed"
        );
        require(msg.value > 0, "Bet amount must be > 0");
        require(betOverAmounts[msg.sender] == 0, "Cannot bet on both over and under");

        if (betOverAmounts[msg.sender] == 0) {
            bettingOver.push(msg.sender);
        }
        betOverAmounts[msg.sender] += msg.value;
        totalOver += msg.value;
    }

    // After the bet date, anyone can call this function to resolve the bet and distribute payouts. Winners receive their original bet plus a proportional share of the losing side’s bets.

    function payBets() public {
        require(block.timestamp > betDate, "Bet date not reached");
        require(!betsPaid, "Bets already paid");
        betsPaid = true;

        int256 latestPrice = getLatestPrice();
        bool overWins = latestPrice > betOverUnderPrice;

        if (overWins) {
            // If no one bet "over", refund those who bet "under"
            if (totalOver == 0) {
                for (uint256 i = 0; i < bettingUnder.length; i++) {
                    address bettor = bettingUnder[i];
                    uint256 amount = betUnderAmounts[bettor];
                    if (amount > 0) {
                        (bool sent,) = payable(bettor).call{value: amount}("");
                        require(sent, "Refund failed");
                    }
                }
                return;
            }
            // Distribute winnings to "over" bettors.
            // Each winner gets: original bet + (their bet / totalOver) * totalUnder.
            for (uint256 i = 0; i < bettingOver.length; i++) {
                address bettor = bettingOver[i];
                uint256 betAmount = betOverAmounts[bettor];
                if (betAmount > 0) {
                    uint256 payout = betAmount + (betAmount * totalUnder) / totalOver;
                    (bool sent,) = payable(bettor).call{value: payout}("");
                    require(sent, "Payout failed");
                }
            }
        } else {
            // Under wins (if the price is equal to or less than the starting price)
            if (totalUnder == 0) {
                for (uint256 i = 0; i < bettingOver.length; i++) {
                    address bettor = bettingOver[i];
                    uint256 amount = betOverAmounts[bettor];
                    if (amount > 0) {
                        (bool sent,) = payable(bettor).call{value: amount}("");
                        require(sent, "Refund failed");
                    }
                }
                return;
            }
            for (uint256 i = 0; i < bettingUnder.length; i++) {
                address bettor = bettingUnder[i];
                uint256 betAmount = betUnderAmounts[bettor];
                if (betAmount > 0) {
                    uint256 payout = betAmount + (betAmount * totalOver) / totalUnder;
                    (bool sent,) = payable(bettor).call{value: payout}("");
                    require(sent, "Payout failed");
                }
            }
        }
    }
}
