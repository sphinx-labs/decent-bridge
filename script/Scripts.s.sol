// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MockEndpoint} from "forge-toolkit/LzChainSetup.sol";
import {DecentEthRouter} from "../src/DecentEthRouter.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {BroadcastMultichainSetup} from "./util/BroadcastMultichainSetup.sol";
import {ParseChainsFromEnvVars} from "./util/ParseChainsFromEnvVars.sol";
import {LoadDecentBridgeDeployedContracts} from "./util/LoadDecentBridgeDeployedContracts.sol";
import {MultichainDeployer} from "../test/common/MultichainDeployer.sol";
import {LoadAllChainInfo} from "forge-toolkit/LoadAllChainInfo.sol";
import {RouterActions} from "../test/common/RouterActions.sol";
import {Sphinx, Network} from "@sphinx-labs/contracts/SphinxPlugin.sol";

contract FakeWeth is ERC20, Owned {
    constructor() ERC20("Wrapped ETH", "WETH", 18) Owned(msg.sender) {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}

contract Common is
    Script,
    Sphinx,
    MultichainDeployer,
    ParseChainsFromEnvVars,
    LoadDecentBridgeDeployedContracts,
    RouterActions
{
    function overrideFtmTestnet() private {
        gasEthLookup["ftm-testnet"] = true;
        wethLookup["ftm-testnet"] = 0x07B9c47452C41e8E00f98aC4c075F5c443281d2A;
    }

    function setUp() public virtual override {
        sphinxConfig.owners = [0x4856e043a1F2CAA8aCEfd076328b4981Aca91000]; // Add owner address(es)
        sphinxConfig.orgId = "clksrkg1v0001l00815670lu8"; // Add org ID
        sphinxConfig.testnets = [
            Network.sepolia,
            Network.optimism_sepolia,
            Network.fantom_testnet
        ];
        sphinxConfig.projectName = "Decent_Bridge";
        sphinxConfig.threshold = 1;

        if (vm.envOr("TESTNET", false)) {
            setRuntime(ENV_TESTNET);
        } else if (vm.envOr("MAINNET", false)) {
            setRuntime(ENV_MAINNET);
        } else {
            setRuntime(ENV_FORK);
        }
        loadAllChainInfo();

        string memory depFile = "deployments.json";
        if (isMainnet()) {
            depFile = string.concat("mainnet_", depFile);
        } else if (isTestnet()) {
            depFile = string.concat("testnet_", depFile);
        } else {
            depFile = string.concat("forknet_", depFile);
        }
        setPathAndFile("deployments", depFile);
    }
}

contract ClearLz is Common {
    function run() public {
        string memory src = vm.envString("src");
        string memory dst = vm.envString("dst");
        loadDecentBridgeContractsForChain(src);
        loadDecentBridgeContractsForChain(dst);
        address srcUa = address(dcntEthLookup[src]);
        address dstUa = address(dcntEthLookup[dst]);
        bytes memory srcPath = abi.encodePacked(srcUa, dstUa);

        console2.log("srcUa", srcUa);
        console2.log("dstUa", dstUa);
        MockEndpoint dstEndpoint = lzEndpointLookup[dst];
        switchTo(dst);
        dealTo(dst, dstUa, 1 ether);
        startImpersonating(dstUa);
        dstEndpoint.forceResumeReceive(lzIdLookup[src], srcPath);
        stopImpersonating();
    }
}

contract RetryLz is Common {
    function run() public {
        string memory src = vm.envString("src");
        string memory dst = vm.envString("dst");
        loadDecentBridgeContractsForChain(src);
        loadDecentBridgeContractsForChain(dst);
        address srcUa = address(dcntEthLookup[src]);
        address dstUa = address(dcntEthLookup[dst]);
        bytes memory srcPath = abi.encodePacked(srcUa, dstUa);

        MockEndpoint dstEndpoint = lzEndpointLookup[dst];
        switchTo(dst);
        bytes
            memory payload = hex"0100000000000000000000000057bedf28c3cb3f019f40f330a2a2b0e0116aa0c2000000000000000100000000000000000000000057bedf28c3cb3f019f40f330a2a2b0e0116aa0c2000000000004dd570000000000000000000000000000000000000000000000000000000000000001000000000000000000000000024d644b055ada775bb20a53c5d90a70698dff990000000000000000000000003547f3cf6dad2ce64b5c308ebd964822220cf577000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000001a44aed0ae8000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000416d4ef57929df6375cc4c689b85f82d81f9763e11faa58be30f287ca66174034e4d6c8dbadb9bfbf9055953f72a76154ecae8148fcc179c71a9a61b1fca74d5471b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        dstEndpoint.retryPayload(lzIdLookup[src], srcPath, payload);
    }
}

contract Bridge is Common {
    function run() public {
        uint64 gas = 120e3;
        uint amount = vm.envUint("bridge_amount");
        string memory src = vm.envString("src");
        string memory dst = vm.envString("dst");
        loadDecentBridgeContractsForChain(src);
        loadDecentBridgeContractsForChain(dst);

        address from = vm.envOr("from", msg.sender);
        address to = vm.envOr("to", msg.sender);

        switchTo(src);
        DecentEthRouter router = routerLookup[src];

        (uint nativeFee, uint zroFee) = router.estimateSendAndCallFee(
            0,
            lzIdLookup[dst],
            to,
            amount,
            gas,
            true,
            ""
        );

        startImpersonating(from);
        router.bridge{value: nativeFee + zroFee + amount}(
            lzIdLookup[dst],
            to,
            amount,
            gas,
            true
        );
        stopImpersonating();
    }
}

contract AddLiquidity is Common {
    function run() public {
        string memory chain = vm.envString("chain");
        uint amount = vm.envUint("liquidity");
        loadDecentBridgeContractsForChain(chain);
        addLiquidity(chain, amount);
    }
}

contract RemoveLiquidity is Common {
    function run() public {
        string memory chain = vm.envString("chain");
        uint amount = vm.envUint("liquidity");
        loadDecentBridgeContractsForChain(chain);
        removeLiquidity(chain, amount);
    }
}

contract WireUp is Common {
    function run() public {
        string memory src = vm.envString("src");
        string memory dst = vm.envString("dst");
        loadDecentBridgeContractsForChain(src);
        loadDecentBridgeContractsForChain(dst);
        wireUpSrcToDstDecentBridge(src, dst);
    }
}

contract Deploy is Common {
    function run() sphinx public {
        string memory chain = networkLookup[block.chainid];
        console2.log("chain is", chain);
        deployDecentBridgeRouterAndRegisterDecentEth(chain);
    }
}
