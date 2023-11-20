// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {OptionsStorage} from "../storage/OptionsStorage.sol";
import {IOptions} from "../interfaces/IOptions.sol";
import {Tokens} from "../utils/Tokens.sol";
import {DataTypes} from "../utils/DataTypes.sol";
import {Events} from "../utils/Events.sol";
import {Utils} from "../utils/Utils.sol";
import {ERC20} from "../lib/ERC20.sol";

/**
 * @title Options
 * @author MoonaLisa
 *
 * @notice This is the main entrypoint of the Options contract.
 */
contract Options is OptionsStorage, IOptions, Tokens {
    /*//////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        totalOptions = 0;
    }

    /*//////////////////////////////////////////////////////////////
                                 PUBLIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOptions
    function exerciseOption(uint256 optionId) public {
        require(msg.sender != address(0), "INVALID ADDRESS");
        Option memory optionToExercise = optionsMap[optionId];
        require(optionToExercise.creator != address(0), "OPTION NOT FOUND");
        Buyer memory buyer = buyersMap[optionId];
        require(!buyer.hasExercised, "ALREADY EXERCISED");
        require(
            buyersMap[optionId].buyerAddress != address(0),
            "NOT BOUGHT YET"
        );
        require(
            block.timestamp > optionToExercise.exerciseStartTime,
            "NOT EXERCISABLE"
        );
        require(block.timestamp < optionToExercise.endTime, "HAS EXPIRED");
        require(buyer.buyerAddress == msg.sender, "NOT YOUR OPTION");

        require(
            ERC20(optionToExercise.asset2).balanceOf(msg.sender) >=
                optionToExercise.strikePrice,
            "INSUFFICIENT TOKEN BALANCE"
        );
        require(
            ERC20(optionToExercise.asset2).allowance(
                msg.sender,
                address(this)
            ) >= optionToExercise.strikePrice,
            "INSUFFICIENT TOKEN ALLOWANCE"
        );

        require(
            ERC20(optionToExercise.asset2).transferFrom(
                msg.sender,
                optionToExercise.creator,
                optionToExercise.strikePrice
            ),
            "ASSET2 TRANSFER FAILED"
        );
        require(
            ERC20(optionToExercise.asset1).transfer(
                msg.sender,
                optionToExercise.totalAmount
            ),
            "ASSET1 TRANSFER FAILED"
        );

        buyersMap[optionId].hasExercised = true;
        emit Events.OptionExercised(optionId, msg.sender);
    }

    /// @inheritdoc IOptions
    function buyOption(uint256 optionId) public virtual {
        require(msg.sender != address(0), "INVALID ADDRESS");
        Option memory optionToBuy = optionsMap[optionId];
        require(optionToBuy.creator != address(0), "OPTION NOT FOUND");
        require(optionToBuy.offerExpiryTime > block.timestamp, "OFFER EXPIRED");
        require(
            buyersMap[optionId].buyerAddress == address(0),
            "ALREADY BOUGHT"
        );

        //  premium is in usdc token
        require(
            ERC20(address(0xe6b8a5CF854791412c1f6EFC7CAf629f5Df1c747))
                .balanceOf(msg.sender) >= optionToBuy.premium,
            "INSUFFICIENT TOKEN BALANCE"
        );
        require(
            ERC20(address(0xe6b8a5CF854791412c1f6EFC7CAf629f5Df1c747))
                .allowance(msg.sender, address(this)) >= optionToBuy.premium,
            "INSUFFICIENT TOKEN ALLOWANCE"
        );

        require(
            ERC20(address(0xe6b8a5CF854791412c1f6EFC7CAf629f5Df1c747))
                .transferFrom(
                    msg.sender,
                    optionToBuy.creator,
                    optionToBuy.premium
                ),
            "ASSET2 TRANSFER FAILED"
        );

        buyersMap[optionId] = Buyer(msg.sender, false);

        emit Events.OptionBought(optionId, msg.sender);
    }

    /// @inheritdoc IOptions
    function createOption(DataTypes.CreateOptionParams memory params) public {
        (
            uint256 endTime,
            uint256 offerExpiryTime,
            uint256 exerciseTime
        ) = checkCreateOption(params);
        require(
            ERC20(params.asset1).transferFrom(
                msg.sender,
                address(this),
                params.amount
            ),
            "ASSET1 TRANSFER FAILED"
        );

        Option memory newOption = Option(
            msg.sender,
            params.symbol,
            endTime,
            params.strikePrice,
            params.amount,
            params.premium,
            params.asset1,
            params.asset2,
            params.isCall,
            offerExpiryTime,
            exerciseTime
        );

        totalOptions++;
        optionsMap[totalOptions] = newOption;

        emit Events.OptionCreated(
            totalOptions,
            msg.sender,
            params.symbol,
            endTime,
            params.strikePrice,
            params.amount,
            params.premium,
            params.asset1,
            params.asset2,
            params.isCall,
            offerExpiryTime,
            exerciseTime
        );
    }

    /*//////////////////////////////////////////////////////////////
                              PUBLIC VIEW
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IOptions
    function checkCreateOption(
        DataTypes.CreateOptionParams memory params
    ) public view returns (uint256, uint256, uint256) {
        require(
            tokensMap[params.asset1].tokenAddress != address(0),
            "ASSET1 NOT FOUND"
        );
        require(
            !tokensMap[params.asset1].isStable,
            "ASSET1 CAN NOT BE A STABLECOIN"
        );
        require(
            tokensMap[params.asset2].tokenAddress != address(0),
            "ASSET2 NOT FOUND"
        );
        require(tokensMap[params.asset1].isAllowed, "ASSET1 NOT ALLOWED");
        require(tokensMap[params.asset2].isAllowed, "ASSET2 NOT ALLOWED");
        require(params.amount > 0, "AMOUNT MUST BE POSITIVE");
        require(params.nbOfDays > 3, "DURATION MUST BE MORE THAN 3 DAYS");
        require(
            params.offerExpiryAfterHours > 0,
            "OFFER EXPIRY TIME MUST BE POSITIVE"
        );
        require(
            params.exerciseTimeInHours > 0,
            "EXERCISE TIME MUST BE POSITIVE"
        );
        require(params.premium > 0, "PREMIUM MUST BE POSITIVE");

        uint256 endTime = Utils.getDurationEndTimeForDays(
            block.timestamp,
            params.nbOfDays
        );
        uint256 offerExpiryTime = Utils.getDurationEndTimeForHours(
            block.timestamp,
            params.offerExpiryAfterHours
        );
        uint256 exerciseTime = Utils.getDurationStartTimeForHours(
            endTime,
            params.exerciseTimeInHours
        );

        require(
            offerExpiryTime < exerciseTime,
            "OFFER EXPIRY TIME MUST BE BEFORE EXERCISE TIME"
        );

        require(
            ERC20(params.asset1).allowance(msg.sender, address(this)) >=
                params.amount,
            "INSUFFICIENT TOKEN ALLOWANCE"
        );

        require(
            ERC20(params.asset1).balanceOf(msg.sender) >= params.amount,
            "INSUFFICIENT TOKEN BALANCE"
        );

        return (endTime, offerExpiryTime, exerciseTime);
    }

    function readOption(uint256 optionId) public view returns (Option memory) {
        return optionsMap[optionId];
    }

    function claimCollateral(uint256 optionId) public {
        require(msg.sender != address(0), "INVALID ADDRESS");
        require(!claimMap[optionId], "ALREADY CLAIMED");
        Option memory optionToClaim = optionsMap[optionId];
        require(optionToClaim.creator != address(0), "OPTION NOT FOUND");
        require(
            optionToClaim.offerExpiryTime < block.timestamp,
            "OFFER NOT EXPIRED YET"
        );

        if (optionToClaim.endTime > block.timestamp) {
            require(
                buyersMap[optionId].buyerAddress == address(0),
                "OPTION IS BOUGHT"
            );
        } else {
            require(!buyersMap[optionId].hasExercised, "OPTION IS EXERCISED");
        }

        require(
            ERC20(optionToClaim.asset1).transfer(
                optionToClaim.creator,
                optionToClaim.totalAmount
            ),
            "ASSET1 TRANSFER FAILED"
        );
        claimMap[optionId] = true;
        emit Events.AssetClaimed(
            msg.sender,
            optionId,
            optionToClaim.totalAmount
        );
    }
}
