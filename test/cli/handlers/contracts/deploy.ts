import { logger, printDivider, printHeader } from "utils";
import { deployContracts } from "../../../scripts/deploy-contracts";
import { showDeploymentPlanAndStatus } from "./status";
import { verifyContracts } from "./verify";

// 1. Interface for options (to remove any)
interface CommandOptions {
  chain?: string;
  rpcUrl?: string;
  privateKey?: string;
  avsOwnerKey?: string;
  avsOwnerAddress?: string;
  executeOwnerTransactions?: boolean;
  skipVerification?: boolean;
  [key: string]: any; // For other commander fields
}

// 2. Helper for extracting Chain (removing duplication)
const getChain = (options: CommandOptions, command: any): string | undefined => {
  return options.chain || 
         (command.parent && command.parent.getOptionValue("chain")) || 
         command.getOptionValue("chain");
};

export const contractsDeploy = async (options: CommandOptions, command: any) => {
  const chain = getChain(options, command);
  
  // chain is already checked in PreActionHook, but it wouldn't hurt to check for typing
  if (!chain) throw new Error("Chain not defined");

  printHeader(`Deploying DataHaven Contracts to ${chain}`);

  const txExecutionOverride = options.executeOwnerTransactions ? true : undefined;

  try {
    logger.info("🚀 Starting deployment...");
    logger.info(`📡 Using chain: ${chain}`);
    if (options.rpcUrl) {
      logger.info(`📡 Using RPC URL: ${options.rpcUrl}`);
    }

    await deployContracts({
      chain: chain,
      rpcUrl: options.rpcUrl,
      // Explicitly use ENV if no option is passed
      privateKey: options.privateKey || process.env.DEPLOYER_PRIVATE_KEY, 
      avsOwnerKey: options.avsOwnerKey,
      avsOwnerAddress: options.avsOwnerAddress,
      txExecution: txExecutionOverride
    });

    printDivider();
  } catch (error) {
    logger.error(`❌ Deployment failed: ${error}`);
    process.exit(1); // IMPORTANT: Crash with error code for CI/CD
  }
};

export const contractsCheck = async (options: CommandOptions, command: any) => {
  const chain = getChain(options, command);
  if (!chain) throw new Error("Chain not defined");

  printHeader(`Checking DataHaven ${chain} Configuration and Status`);

  try {
    logger.info("🔍 Showing deployment plan and status");
    await showDeploymentPlanAndStatus(chain);
  } catch (error) {
    logger.error(`❌ Check status failed: ${error}`);
    process.exit(1);
  }
};

export const contractsVerify = async (options: CommandOptions, command: any) => {
  const chain = getChain(options, command);
  if (!chain) throw new Error("Chain not defined");

  printHeader(`Verifying DataHaven Contracts on ${chain} Block Explorer`);

  if (options.skipVerification) {
    logger.info("⏭️ Skipping verification as requested");
    return;
  }

  try {
    const verifyOptions = {
      ...options,
      chain: chain
    };
    await verifyContracts(verifyOptions);
    printDivider();
  } catch (error) {
    logger.error(`❌ Verification failed: ${error}`);
    process.exit(1); // Not necessary if verification doesn't block the deployment, but good to know.
  }
};

export const contractsPreActionHook = async (thisCommand: any) => {
  // The logic for extracting chain here is a little different (via getOptionValue directly),
  // but you can use the same principle or leave it as is, since the options here are not yet fully formed.
  let chain = thisCommand.getOptionValue("chain");

  if (!chain && thisCommand.parent) {
    chain = thisCommand.parent.getOptionValue("chain");
  }

  const privateKey = thisCommand.getOptionValue("privateKey");

  // The array of valid networks is moved to a constant
  const supportedChains = ["hoodi", "mainnet", "anvil"];

  if (!chain) {
    logger.error("❌ Chain is required. Use --chain option (hoodi, mainnet, anvil)");
    process.exit(1);
  }

  if (!supportedChains.includes(chain)) {
    logger.error(`❌ Unsupported chain: ${chain}. Supported chains: ${supportedChains.join(", ")}`);
    process.exit(1);
  }

  if (!privateKey && !process.env.DEPLOYER_PRIVATE_KEY) {
    logger.warn(
      "⚠️ Private key not provided. Will use DEPLOYER_PRIVATE_KEY environment variable if set, or default Anvil key."
    );
  }
};
