// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

// EigenLayer imports
import {
    IAllocationManagerTypes
} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import { StrategyBase } from "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
import { IStrategy } from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

// OpenZeppelin imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Testing imports
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Logging } from "../utils/Logging.sol";
import { ELScriptStorage } from "../utils/ELScriptStorage.s.sol";
import { DHScriptStorage } from "../utils/DHScriptStorage.s.sol";
import { Accounts } from "../utils/Accounts.sol";

/**
 * @title SignUpOperatorBase
 * @notice Base contract for signing up validators / BSP / MSP operators
 */
abstract contract SignUpOperatorBase is
    Script,
    ELScriptStorage,
    DHScriptStorage,
    Accounts
{
    using SafeERC20 for IERC20;

    // Progress indicator
    uint16 public deploymentStep = 0;
    uint16 public totalSteps = 4; // Now we count 4 steps (load contracts, stake, Eigen, DataHaven)

    function _logProgress() internal {
        deploymentStep++;
        Logging.logProgress(deploymentStep, totalSteps);
    }

    // -------------------------------------------------
    // Abstract methods – must be overridden by children
    // -------------------------------------------------
    function _getOperatorSetId() internal view virtual returns (uint32);
    function _addToAllowlist() internal virtual;
    function _getOperatorTypeName() internal view virtual returns (string memory);

    // -------------------------------------------------
    // Main script entry point
    // -------------------------------------------------
    function run() public {
        // ---- 0. Basic setup -------------------------------------------------
        string memory network = vm.envOr("NETWORK", string("anvil"));
        Logging.logHeader(string.concat("SIGN UP DATAHAVEN ", _getOperatorTypeName()));
        console.log("|  Network: %s", network);
        console.log("|  Timestamp: %s", vm.toString(block.timestamp));
        Logging.logFooter();

        // ---- 1. Load contract addresses --------------------------------------
        _loadELContracts(network);
        Logging.logInfo(string.concat("Loaded EigenLayer contracts for network: ", network));

        _loadDHContracts(network);
        Logging.logInfo(string.concat("Loaded DataHaven contracts for network: ", network));

        _logProgress();

        // ---- 2. Stake tokens into strategies ---------------------------------
        Logging.logSection("Staking Tokens into Strategies");

        for (uint256 i = 0; i < deployedStrategies.length; i++) {
            address strategyAddr = deployedStrategies[i].strategy;
            require(strategyAddr != address(0), "Strategy address is zero");

            IERC20 linkedToken = IStrategy(strategyAddr).underlyingToken();

            uint256 balance = linkedToken.balanceOf(_operator);
            Logging.logInfo(
                string.concat(
                    "Strategy ",
                    vm.toString(i),
                    " underlying token: ",
                    vm.toString(address(linkedToken)),
                    " - Operator balance: ",
                    vm.toString(balance)
                )
            );

            require(balance > 0, "Operator does not have a balance of the linked token");
            uint256 balanceToStake = balance / 10;
            require(balanceToStake > 0, "Balance too low to stake (need at least 10 tokens)");

            vm.startBroadcast(_operatorPrivateKey);
            linkedToken.safeApprove(address(strategyManager), balanceToStake);
            strategyManager.depositIntoStrategy(
                deployedStrategies[i].strategy,
                linkedToken,
                balanceToStake
            );
            vm.stopBroadcast();

            Logging.logStep(
                string.concat(
                    "Staked ",
                    vm.toString(balanceToStake),
                    " tokens for strategy ",
                    vm.toString(i)
                )
            );
        }

        _logProgress();

        // ---- 3. Register as EigenLayer operator --------------------------------
        Logging.logSection("Registering as EigenLayer Operator");

        if (!delegation.isOperator(_operator)) {
            address initDelegationApprover = address(0);
            uint32 allocationDelay = 0;
            string memory metadataURI = "";

            vm.broadcast(_operatorPrivateKey);
            delegation.registerAsOperator(initDelegationApprover, allocationDelay, metadataURI);
            Logging.logStep(
                string.concat("Registered operator in EigenLayer: ", vm.toString(_operator))
            );
        } else {
            Logging.logInfo("Operator already registered in EigenLayer");
        }

        // Show operator shares for each strategy
        Logging.logSection("Operator Shares Information");
        for (uint256 i = 0; i < deployedStrategies.length; i++) {
            uint256 operatorShares = delegation.operatorShares(
                _operator,
                deployedStrategies[i].strategy
            );
            Logging.logInfo(
                string.concat(
                    "Operator shares for strategy ",
                    vm.toString(i),
                    ": ",
                    vm.toString(operatorShares)
                )
            );
        }

        _logProgress();

        // ---- 4. Register as DataHaven operator ---------------------------------
        Logging.logSection(string.concat("Registering as DataHaven ", _getOperatorTypeName()));

        _addToAllowlist();
        Logging.logStep(
            string.concat(
                "Added operator to ",
                _getOperatorTypeName(),
                " allowlist of DataHaven service"
            )
        );

        uint32[] memory operatorSetIds = new uint32[](1);
        operatorSetIds[0] = _getOperatorSetId();

        IAllocationManagerTypes.RegisterParams memory registerParams = IAllocationManagerTypes
            .RegisterParams({
                avs: address(serviceManager),
                operatorSetIds: operatorSetIds,
                data: abi.encodePacked(_operatorSolochainAddress)
            });

        vm.broadcast(_operatorPrivateKey);
        allocationManager.registerForOperatorSets(_operator, registerParams);
        Logging.logStep(
            string.concat("Registered ", _getOperatorTypeName(), " in DataHaven service")
        );

        // ---- 5. Finish --------------------------------------------------------
        Logging.logHeader("OPERATOR SETUP COMPLETE");
        Logging.logInfo(string.concat(_getOperatorTypeName(), ": ", vm.toString(_operator)));
        Logging.logInfo(
            string.concat(
                "Successfully configured ",
                _getOperatorTypeName(),
                " for DataHaven"
            )
        );
        Logging.logFooter();

        _logProgress(); // final step
    }
}
