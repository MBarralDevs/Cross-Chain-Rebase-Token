// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenPool} from "@chainlink/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@chainlink/src/v0.8/ccip/libraries/Pool.sol";
import {IERC20} from "@chainlink/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    constructor(
        IERC20 _token,
        uint8 localTokenDecimals,
        address[] memory _allowlist,
        address _rmnProxy,
        address _router
    ) TokenPool(_token, 18, _allowlist, _rmnProxy, _router) {}

    //Function which burn the user's tokens on the source chain
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        virtual
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        //1 - Validate the lock or burn input with CCIP
        _validateLockOrBurn(lockOrBurnIn);

        //2 - We want to pass to the destination chain the interest rate of the user in the source chain
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUsersInterestRate(lockOrBurnIn.originalSender);

        //3 - We can now burn the user's tokens on source chain
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        //4 - We return the destination token address and the user interest rate as pool data
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        virtual
        override
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        //1 - Validate the release or mint input with CCIP
        _validateReleaseOrMint(releaseOrMintIn);

        //2 - Get the user interest rate from the pool data
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));

        //3 - We mint the user's tokens on the destination chain
        IRebaseToken(address(i_token)).mint(releaseOrMintIn.receiver, releaseOrMintIn.amount);
    }
}
