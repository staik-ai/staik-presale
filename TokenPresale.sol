// SPDX-License-Identifier: UNLICENSED

//     ███████╗████████╗ █████╗ ██╗██╗  ██╗    █████╗ ██╗
//     ██╔════╝╚══██╔══╝██╔══██╗██║██║ ██╔╝   ██╔══██╗██║
//     ███████╗   ██║   ███████║██║█████╔╝    ███████║██║
//     ╚════██║   ██║   ██╔══██║██║██╔═██╗    ██╔══██║██║
//     ███████║   ██║   ██║  ██║██║██║  ██╗██╗██║  ██║██║
//     ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./Whitelist.sol";

contract Presale is Ownable, Pausable, Whitelist {

    ERC20 public immutable token; // Token contract instance.

    mapping(address => bool) public contractsWhiteList;
    
    address payable presaleOwner; // Presale owner wallet address, which must be the same than Token contract owner address.
    address payable presaleContract;
    address private presaleLiquidityWallet = address(0); // Presale liquidity wallet.
    
    // 1.5 Billion STAIK (1,500,000,000) deposited and available in the pre-sale (15% of total supply) worth approx $150,000
    uint256 private presaleRate = 1500000; // How many STAIK tokens that can be purchased for 1 ETH (1,500,000 STAIK per ETH)
    
    // When presale ends, nobody will be able to buy tokens from this contract. (Actual Date TBC)
    uint256 public presaleEndsDate = 9999999; 
    
    uint256 public constant minContribLimit = 200000000000000000; // The minimum purchase in ETH - 0.2 ETH (expressed in Wei)
    uint256 public constant maxContribLimit = 1000000000000000000; // The maximum purchase in ETH - 1 ETH (expressed in Wei)

    // 15% of STAIK total supply (1,500,000,000 - 1.5 Billion) reserved for whitelisted founding members
    uint256 public constant hardCap = 1000000000000000000000; // The maximum limit supply in ETH - 1,000 ETH (expressed in Wei)

    // unlock date when buyers can withdraw their STAIK - Expressed as Epoch (Actual Date TBC)
    uint256 public unlockDate = 9999999;

   
    event BuyTokens (address, uint256, address, uint256);
    event TransferTokens (address, uint256);

    modifier onlyWhitelisted() {
        if(!whitelist()){
            _;
        }else{
            require(contractsWhiteList[msg.sender], "You are not whitelisted");
            _;
        }
    }
    
    constructor (address payable _staikTokenContract) payable {
        token = ERC20(_staikTokenContract);
        presaleOwner = payable(msg.sender);
        presaleContract = payable(address(this));
        token.setPresaleContractAddress();
        addLiquidityToPresale(presaleRate*hardCap);
    }

    /**
     * @dev Adds STAIK token liquidity to presale contract.
     */
    function addLiquidityToPresale(uint256 _amount) onlyOwner public returns (bool) {
        require(token.approvePresaleContract(_amount), "not allowed");
        token.transferFrom(presaleOwner, presaleContract, _amount);
        return true;
    }

    /**
     * @dev Purchase (Deposit ETH to get STAIK)
     */
    mapping(address => bool) public hasPurchased;
    mapping(address => LockedToken[]) public lockedTokens;

    struct LockedToken {
        uint256 amount;
        uint256 unlockDate;
        bool withdrawn;
    } 

    function buyStaik() public payable onlyWhitelisted whenNotPaused returns (bool) {
        // check that whitelisted wallet hasn't already tried to make a purchase
        require(!hasPurchased[msg.sender], "You have already purchased tokens");
        // check that pre-sale hasn't ended
        require(block.timestamp < presaleEndsDate, "Presale has now finished");
        // check that purchaser is sending at least 0.2 ETH
        require(msg.value >= minContribLimit, "Insufficient funds. You need to send at least 0.2 ETH");
        // check that purchase isn't sending more than 1.0 ETH
        require(msg.value <= maxContribLimit, "You're trying to send too much ETH! Maximum 1.0 ETH per whitelisted wallet");
        // security measure - check that pre-sale hardcap isn't exceeded
        require(presaleContractETHBalance() <= hardCap, "You can't buy any more STAIK tokens");
        // call the "tokenPrice()" function... ETH multipled by preSaleRate
        uint256 _numTokensToBuy = tokenPrice(msg.value);
        // security measure - check there's enough STAIK in the pre-sale
        require(_numTokensToBuy <= availableStaikInPresale(), "Insufficient liquidity. You cannot purchase this many tokens");
        // ensure the buyer doesn't try to purchase more than 2m STAIK
        require(token.balanceOf(msg.sender) + _numTokensToBuy <= 2000000, "You cannot purchase more than 2 million tokens");
        // set boolean to true - can only make one attempt at purchasing
        hasPurchased[msg.sender] = true;
        // lock the tokens until the specified unlock date
        lockedTokens[msg.sender].push(LockedToken({
            amount: _numTokensToBuy,
            unlockDate: unlockDate,
            withdrawn: false
        }));
        return true;
    }

    /**
     * @dev Withdraws all unlocked tokens for the caller.
     */
    function withdrawUnlockedTokens() public {
        uint256 totalTokens = 0;
        // loop through all locked tokens for the caller
        for (uint256 i = 0; i < lockedTokens[msg.sender].length; i++) {
            LockedToken storage lockedToken = lockedTokens[msg.sender][i];
            // check if token is unlocked and not already withdrawn
            if (block.timestamp >= lockedToken.unlockDate && !lockedToken.withdrawn) {
                totalTokens += lockedToken.amount;
                lockedToken.withdrawn = true;
            }
        }
        // transfer unlocked tokens to caller
        token.transfer(msg.sender, totalTokens);
    }

    receive() external payable {
        buyStaik();
    }

    /**
     * @dev Returns the equivalent STAIK of an ETH amount.
     */
    function tokenPrice(uint256 _ETHToSell) public payable returns (uint256) {
        return (_ETHToSell * presaleRate);
    }

    /**
     * @dev Withdraw any outstanding ETH and STAIK from the contract after pre-sale ends.
     */
    function withdrawRemainingFunds() public onlyOwner {
        require(block.timestamp > presaleEndsDate, "Presale has not yet ended");
        uint256 remainingETH = address(this).balance;
        uint256 remainingTokens = token.balanceOf(address(this));
        require(remainingETH > 0 || remainingTokens > 0, "There are no remaining funds or tokens");
        if (remainingETH > 0) {
            payable(owner()).transfer(remainingETH);
        }
        if (remainingTokens > 0) {
            token.transfer(owner(), remainingTokens);
        }
    }

    /**
     * @dev Returns the ETH balance of presale contract.
     */
    function presaleContractETHBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Returns the STAIK balance of presale contract.
     */
    function availableStaikInPresale() public view returns (uint256) {
        return token.balanceOf(presaleContract);
    }

    /**
     * Returns the STAIK balance of any address.
     */
    function balanceOf(address _address) public view returns (uint) {
        return token.balanceOf(_address);
    }

    /**
     * Returns the allowance of an address.
     */
    function allowance(address _owner, address _spender) public view returns (uint256) {
        return token.allowance(_owner, _spender);
    }

    /**
     * Adds an address to the whitelist of presale contract.
     */
    function addToWhiteList(address _address) public onlyOwner {
        contractsWhiteList[_address] = true;
    }

    /**
     * Adds multiple addresses to the whitelist of presale contract.
     */
    function addManyToWhitelist(address[] memory _addresses) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            contractsWhiteList[_addresses[i]] = true;
        }
    }

    /**
     * Removes an address from the whitelist of presale contract.
     */
    function removeFromWhiteList(address _address) public onlyOwner {
        contractsWhiteList[_address] = false;
    }

    /**
     * Enables the whitelist.
     */
    function enableWhitelist() public onlyOwner {
        _enableWhitelist();
    }

    /**
     * Disables the whitelist.
     */
    function disableWhitelist() public onlyOwner {
        _disableWhitelist();
    }

    /**
     * Checks if an address is whitelisted.
     */
    function isWhitelisted(address _address) public view returns (bool) {
        return contractsWhiteList[_address];
    }
}
