//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface MilAuthInterface {
    function isDev(address _who) external view returns (bool);

    function checkGameRegister(address _gameAddr) external view returns (bool);
}

interface MillionaireInterface {
    function gameBuyMfAndAff(address _addr, uint256 _affID, uint256 buyMfAmount) external payable;
}

contract Milevents {

    // fired whenever a player registers
    event onNewPlayer
    (
        address indexed playerAddress,
        uint256 playerID,
        uint256 timeStamp
    );

    event onAffiliatePayout
    (
        address indexed affiliateAddress,
        address indexed buyerAddress,
        uint256 eth,
        uint256 timeStamp
    );

    // fired whenever an player win the playround
    event onPlayerWin(
        address indexed addr,
        uint256 roundID,
        uint256 userCode,
        uint256 chainCode,
        uint256 winGrade
    );

    // fired whenever an player win the playround
    event onPlayerReward(
        address indexed addr,
        uint256 roundID,
        uint256 winAmount,
        uint256 winNum1,
        uint256 winNum2,
        uint256 winNum3
    );

    event onBuyMFCoins(
        address indexed addr,
        uint256 ethAmount,
        uint256 mfAmount,
        uint256 timeStamp
    );

    event onSellMFCoins(
        address indexed addr,
        uint256 ethAmount,
        uint256 mfAmount,
        uint256 timeStamp
    );

}

contract Millionaire is MillionaireInterface, Milevents {
    using SafeMath for *;
    using MFCoinsCalc for uint256;

    //==============================================================================
    //     _ _  _  |`. _     _ _ |_ | _  _  .
    //    (_(_)| |~|~|(_||_|| (_||_)|(/__\  .  (game settings)
    //=================_|===========================================================
    string  constant private    name_ = "Millionaire Official";
    uint256 private             sequence_ = 100000;                      // affiliate id sequence

    MilAuthInterface constant private milAuth_ = MilAuthInterface(0x54Af34b74DFb891923d5728Cae0D5d2bf7146269);

    uint256     public          mfCoinPool_;                    // MFCoin Pool
    uint256     public          totalSupply_;                   // MFCoin current supply

    address constant private fundAddr_ = 0x94fEd42424FEf4100db02895325cC385ED23c383; // foundation address

    mapping(address => uint256) private balance_;               // player coin balance
    mapping(uint256 => address) private plyrAddr_;             // (id => address) returns player id by address
    mapping(address => Mildatasets.Player) private plyr_;      // (addr => data) player data

    //==============================================================================
    //     _ _  _  _|. |`. _  _ _  .
    //    | | |(_)(_||~|~|(/_| _\  .  (these are safety checks)
    //==============================================================================

    /**
     * @dev prevents contracts from interacting with Millionare
     */
    modifier isHuman() {
        address _addr = msg.sender;
        uint256 _codeLength;

        assembly {_codeLength := extcodesize(_addr)}
        require(_codeLength == 0, "sorry humans only");
        _;
    }

    /**
     * @dev check sender must be devs
     */
    modifier onlyDevs()
    {
        require(milAuth_.isDev(msg.sender) == true, "msg sender is not a dev");
        _;
    }

    function getbalance() public view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev game buy mf and gen affiliate
     */
    function gameBuyMfAndAff(address _addr, uint256 _affID, uint256 buyMfAmount)
    external
    payable
    {
        require(milAuth_.checkGameRegister(msg.sender), "no authrity");
        require(buyMfAmount > 0 && buyMfAmount <= msg.value, "invalid number");

        if (plyr_[_addr].playerID == 0) {
            plyrAddr_[++sequence_] = _addr;
            plyr_[_addr].playerID = sequence_;
            emit onNewPlayer(_addr, sequence_, block.timestamp);
        }

        uint256 tmpAffID = plyr_[_addr].laff;
        if (tmpAffID == 0 && plyrAddr_[_affID] != _addr && plyrAddr_[_affID] != address(0)) {
            plyr_[_addr].laff = _affID;
            tmpAffID = _affID;
        }
        uint256 affAmount = msg.value.sub(buyMfAmount);
        if (affAmount > 0 && tmpAffID > 0) {
            address affAddr = plyrAddr_[tmpAffID];
            plyr_[affAddr].affTotal = plyr_[affAddr].affTotal.add(affAmount);
            payable(affAddr).transfer(affAmount);
            buyMFCoins(_addr, buyMfAmount);
        } else {
            buyMFCoins(_addr, msg.value);
        }

    }

    /**
     * @dev sell coin to eth
     * @param _coins sell coins
     */
    function sellMFCoins(uint256 _coins) public {
        require(balance_[msg.sender] >= _coins, "coins amount is out of range");

        uint256 _eth = totalSupply_.ethRec(_coins);
        mfCoinPool_ = mfCoinPool_.sub(_eth);
        totalSupply_ = totalSupply_.sub(_coins);
        balance_[msg.sender] = balance_[msg.sender].sub(_coins);
        payable(msg.sender).transfer(_eth);

        emit onSellMFCoins(msg.sender, _eth, _coins, block.timestamp);
    }

    /**
     * @dev convert eth to coin
     * @param _addr user address
     * @return return back coins
     */
    function buyMFCoins(address _addr, uint256 _eth) private returns (uint256) {
        uint256 _coins = calcCoinsReceived(_eth);
        mfCoinPool_ = mfCoinPool_.add(_eth);
        totalSupply_ = totalSupply_.add(_coins);
        balance_[_addr] = balance_[_addr].add(_coins);

        emit onBuyMFCoins(_addr, _eth, _coins, block.timestamp);
        return _coins;
    }

    /**
     * @dev returns player info based on address
     * @param _addr address of the player you want to lookup
     * @return player ID
     * @return player MFCoin
     * @return affiliate vault
     */
    function getPlayerAccount(address _addr)
    public
    view
    returns (uint256, uint256, uint256)
    {
        return (
        plyr_[_addr].playerID,
        balance_[_addr],
        plyr_[_addr].affTotal
        );
    }

    /**
     * @dev give _eth can convert how much MFCoin
     * @param _eth eth i will give
     * @return MFCoin will return back
     */
    function calcCoinsReceived(uint256 _eth)
    public
    view
    returns (uint256)
    {
        return mfCoinPool_.keysRec(_eth);
    }

    /**
     * @dev returns current eth price for X coins.
     * @param _coins number of coins desired (in 18 decimal format)
     * @return amount of eth needed to send
     */
    function calcEthReceived(uint256 _coins)
    public
    view
    returns (uint256)
    {
        if (totalSupply_ < _coins) {
            return 0;
        }
        return totalSupply_.ethRec(_coins);
    }

    function getMFBalance(address _addr)
    public
    view
    returns (uint256) {
        return balance_[_addr];
    }

    // function kill() onlyDevs public {
    //     selfdestruct(payable(msg.sender));
    //     // 销毁合约
    // }
}

//==============================================================================
//   __|_ _    __|_ _  .
//  _\ | | |_|(_ | _\  .
//==============================================================================
library Mildatasets {

    // between `DRAWN' and `ASSIGNED', someone need to claim winners.
    enum RoundState {
        UNKNOWN, // aim to differ from normal states
        STARTED, // start current round
        STOPPED         // stop current round
    }

    // RewardType
    enum RewardType {
        UNKNOWN, // default
        DRAW, // draw code
        ASSIGN, // assign winner
        END, // end game
        CLIAM           // winner cliam
    }

    struct Player {
        uint256 playerID;       // Player id(use to affiliate other player)
        uint256 affTotal;       // affiliate total vault
        uint256 laff;           // last affiliate id used
    }

    struct Round {
        uint256 roundDeadline;      // deadline to end round
        uint256 pot;                // pot
        uint256 realPot;            // real pot
        uint256 rewardPot;          // already reward
        uint256 blockNumber;        // draw block number(last one)
        RoundState state;              // round state
        uint256 drawCode;           // draw code
        Winning win1;               // win1 info
        Winning win2;               // win2 info
        Winning win3;               // win3 info
        mapping(address => bool) winnAssign;         // winners' is assign
    }

    struct Winning {
        uint256 totalNum;           // total number
        mapping(address => uint256) winnerNum;          // winners' number
        address[] winners;            // winners
    }

}

/**
 * @title SafeMath v0.1.9
 * @dev Math operations with safety checks that throw on error
 * change notes:  original SafeMath library from OpenZeppelin modified by Inventor
 * - added sqrt
 * - added sq
 * - added pwr
 * - changed asserts to requires with error log outputs
 * - removed div, its useless
 */
library SafeMath {

    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b)
    internal
    pure
    returns (uint256 c)
    {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        require(c / a == b, "SafeMath mul failed");
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    /**
    * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b)
    internal
    pure
    returns (uint256)
    {
        require(b <= a, "SafeMath sub failed");
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b)
    internal
    pure
    returns (uint256 c)
    {
        c = a + b;
        require(c >= a, "SafeMath add failed");
        return c;
    }

    /**
     * @dev gives square root of given x.
     */
    function sqrt(uint256 x)
    internal
    pure
    returns (uint256 y)
    {
        uint256 z = ((add(x, 1)) / 2);
        y = x;
        while (z < y)
        {
            y = z;
            z = ((add((x / z), z)) / 2);
        }
    }

    /**
     * @dev gives square. multiplies x by x
     */
    function sq(uint256 x)
    internal
    pure
    returns (uint256)
    {
        return (mul(x, x));
    }

    /**
     * @dev x to the power of y
     */
    function pwr(uint256 x, uint256 y)
    internal
    pure
    returns (uint256)
    {
        if (x == 0)
            return (0);
        else if (y == 0)
            return (1);
        else
        {
            uint256 z = x;
            for (uint256 i = 1; i < y; i++)
                z = mul(z, x);
            return (z);
        }
    }

    function min(uint x, uint y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }

    function max(uint x, uint y) internal pure returns (uint z) {
        return x >= y ? x : y;
    }
}

//==============================================================================
//  |  _      _ _ | _  .
//  |<(/_\/  (_(_||(_  .
//=======/======================================================================
library MFCoinsCalc {
    using SafeMath for *;
    /**
     * @dev calculates number of keys received given X eth
     * @param _curEth current amount of eth in contract
     * @param _newEth eth being spent
     * @return amount of ticket purchased
     */
    function keysRec(uint256 _curEth, uint256 _newEth)
    internal
    pure
    returns (uint256)
    {
        return (keys((_curEth).add(_newEth)).sub(keys(_curEth)));
    }

    /**
     * @dev calculates amount of eth received if you sold X keys
     * @param _curKeys current amount of keys that exist
     * @param _sellKeys amount of keys you wish to sell
     * @return amount of eth received
     */
    function ethRec(uint256 _curKeys, uint256 _sellKeys)
    internal
    pure
    returns (uint256)
    {
        return ((eth(_curKeys)).sub(eth(_curKeys.sub(_sellKeys))));
    }

    /**
     * @dev calculates how many keys would exist with given an amount of eth
     * @return number of keys that would exist
     */
    function keys(uint256 _v)
    internal
    pure
    returns (uint256) {
        return (((((_v).mul(100000000).mul(2000000000000000000000000)).add(99999900000025000000000000000000000000000000)).sqrt()).sub(9999995000000000000000)) / (100000000);
    }

    /**
     * @dev calculates how much eth would be in contract given a number of keys
     * @param _keys number of keys "in contract"
     * @return eth that would exists
     */
    function eth(uint256 _keys)
    internal
    pure
    returns (uint256)
    {
        return (((_keys.sq()).add((1999999).mul(_keys.mul(100000000)))) / (2)) / ((100000000).sq());
    }
}