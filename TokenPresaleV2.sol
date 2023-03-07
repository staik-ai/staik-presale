// SPDX-License-Identifier: UNLICENSED

// updated to accept USDC instead of ETH to avoid situations were ETH value could decrease
// between time of pre-sale and main sale, removing the advantage for pre-sale investors

//     ███████╗████████╗ █████╗ ██╗██╗  ██╗    █████╗ ██╗
//     ██╔════╝╚══██╔══╝██╔══██╗██║██║ ██╔╝   ██╔══██╗██║
//     ███████╗   ██║   ███████║██║█████╔╝    ███████║██║
//     ╚════██║   ██║   ██╔══██║██║██╔═██╗    ██╔══██║██║
//     ███████║   ██║   ██║  ██║██║██║  ██╗██╗██║  ██║██║
//     ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./Whitelist.sol";

contract TokenPresale is Ownable, Pausable, Whitelist {
    // STAIK Token contract instance
    IERC20 public immutable staikToken; 
    // USDC token contract instance
    IERC20 public immutable usdcToken; 
    // STAIK token contract address
    address public staikAddress; 
    // USDC token contract address
    address public usdcAddress; 

    // Presale owner wallet address, which must be the same as the token contract owner address.
    address payable public presaleOwner; 
    address payable public presaleContract;
    address private presaleLiquidityWallet = address(0); // Presale liquidity wallet.

    uint256 private presaleRate = 10000; // How many STAIK tokens can be purchased for 1 USDC (10,000 STAIK per USDC).

    // end date expressed as Epoch
    uint256 public presaleEndsDate = 9999999;

    uint256 public constant minContribLimit = 50 * 10 ** 6; // The minimum purchase in USDC - 50 USDC.
    uint256 public constant maxContribLimit = 200 * 10 ** 6; // The maximum purchase in USDC - 200 USDC.

    uint256 public constant hardCap = 200000; // The maximum limit supply in USDC ($200,000).

    // date buyers can unlock their STAIK
    uint256 public unlockDate = 9999999;

    mapping(address => bool) public contractsWhiteList;
    mapping(address => bool) public hasPurchased;
    mapping(address => LockedToken[]) public lockedTokens;

    struct LockedToken {
        uint256 amount;
        uint256 unlockDate;
        bool withdrawn;
    }

    event LiquidityAdded(address indexed owner, uint256 staikValue);
    event BuyTokens(address indexed buyer, uint256 usdcAmount, address indexed recipient, uint256 numTokens);
    event TransferTokens(address indexed recipient, uint256 numTokens);
    

    constructor (address _staikTokenAddress, address _usdcTokenAddress) payable {
        staikToken = IERC20(_staikTokenAddress);
        usdcToken = IERC20(_usdcTokenAddress);
        presaleOwner = payable(msg.sender);
        presaleContract = payable(address(this));
        addLiquidityToPresale(presaleRate*hardCap);
        usdcAddress = _usdcTokenAddress;
        staikAddress = _staikTokenAddress;
    }

    modifier onlyWhitelisted() {
        if (!whitelist()) {
            _;
        } else {
            require(contractsWhiteList[msg.sender], "You are not whitelisted");
            _;
        }
    }

    function buyStaik(address _recipient, uint256 _usdcAmount) public onlyWhitelisted whenNotPaused returns (bool) {
        require(!hasPurchased[msg.sender], "You have already purchased tokens.");
        require(block.timestamp < presaleEndsDate, "Presale has now finished.");
        require(_usdcAmount >= minContribLimit, "Insufficient funds. You need to send at least 200 USDC.");
        require(_usdcAmount <= maxContribLimit, "You're trying to send too much USDC! Maximum 1000 USDC per whitelisted wallet.");
        require(presaleContractUsdcBalance() <= hardCap, "You can't buy any more STAIK tokens.");
        uint256 _numTokensToBuy = tokenPrice(_usdcAmount);
        require(_numTokensToBuy <= availableStaikInPresale(), "Insufficient liquidity. You cannot purchase this many tokens.");
        require(staikToken.balanceOf(msg.sender) + _numTokensToBuy <= 2000000, "You cannot purchase more than 2 million tokens.");
        hasPurchased[msg.sender] = true;
        lockedTokens[_recipient].push(LockedToken({
            amount: _numTokensToBuy,
            unlockDate: unlockDate,
            withdrawn: false
        }));
        emit BuyTokens(msg.sender, _usdcAmount, _recipient, _numTokensToBuy);
        return true;
    }

    function addLiquidityToPresale(uint256 _amount) onlyOwner public returns (bool) {
        require(staikToken.transferFrom(msg.sender, address(this), _amount), "STAIK transfer failed.");
        uint256 staikBalance = staikToken.balanceOf(address(this));
        require(staikBalance >= _amount, "STAIK transfer failed.");
        staikToken.transferFrom(presaleOwner, presaleContract, _amount);
        emit LiquidityAdded(presaleOwner, staikBalance);
        return true;
    }

    // to be called by buyer once unlock date has passed
    function withdrawUnlockedTokens() public {
        uint256 totalTokens = 0;
        // Loop through all locked tokens for the caller.
        for (uint256 i = 0; i < lockedTokens[msg.sender].length; i++) {
            LockedToken storage lockedToken = lockedTokens[msg.sender][i];
            // Check if token is unlocked and not already withdrawn.
            if (block.timestamp >= lockedToken.unlockDate && !lockedToken.withdrawn) {
                totalTokens += lockedToken.amount;
                lockedToken.withdrawn = true;
            }
        }
        // transfer the STAIK tokens
        staikToken.transfer(msg.sender, totalTokens);
        emit TransferTokens(msg.sender, totalTokens);
    }

    function tokenPrice(uint256 _usdcToSell) public view returns (uint256) {
        return (_usdcToSell * presaleRate);
    }

    function withdrawRemainingFunds() public onlyOwner {
        require(block.timestamp > presaleEndsDate, "Presale has not yet ended.");
        uint256 remainingUSDC = usdcToken.balanceOf(address(this));
        uint256 remainingTokens = staikToken.balanceOf(address(this));
        require(remainingUSDC > 0 || remainingTokens > 0, "There are no remaining funds or tokens.");
        if (remainingUSDC > 0) {
            require(usdcToken.transfer(owner(), remainingUSDC), "USDC transfer failed.");
        }
        if (remainingTokens > 0) {
            staikToken.transfer(owner(), remainingTokens);
        }
    }

    function presaleContractUsdcBalance() public view returns (uint256) {
        return usdcToken.balanceOf(address(this));
    }

    function availableStaikInPresale() public view returns (uint256) {
        return staikToken.balanceOf(presaleContract);
    }

    function usdcBalanceOf(address _address) public view returns (uint256) {
        return usdcToken.balanceOf(_address);
    }
}
