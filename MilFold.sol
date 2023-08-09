//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface MilAuthInterface {
    function isDev(address _who) external view returns(bool);
    function checkGameRegister(address _gameAddr) external view returns(bool);
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

contract MilFold is Milevents {
    using SafeMath for *;

//==============================================================================
//     _ _  _  |`. _     _ _ |_ | _  _  .
//    (_(_)| |~|~|(_||_|| (_||_)|(/__\  .  (game settings)
//=================_|===========================================================
    uint256     constant private    rndMax_ = 86400;                                    	// max length a round timer can be
    uint256     constant private    entertainedTime = 1800;                                  // entertained time before current round end
    address     constant private    fundAddr_ = 0x94fEd42424FEf4100db02895325cC385ED23c383; // foundation address
	uint256 	constant private 	UNIT = 0.001 ether;         								// unit
    uint256     constant private    TICKET_VALUE = UNIT;           		                    // reward who claim an winner

    uint256     private             rID_;                                                   // current round;
    bool        private             activated_;                                             // mark contract is activated;
    
    MillionaireInterface constant private millionaire_ = MillionaireInterface(0xA429Fd58A81D9a92C9a9169892a1f11A98700142);
    MilAuthInterface constant private milAuth_ = MilAuthInterface(0x54Af34b74DFb891923d5728Cae0D5d2bf7146269);

    mapping (uint256 => Mildatasets.Round) private round_;                                  // (rID => data) returns round data
    mapping (address => uint256) private playerWinTotal_;                                   // (addr => eth) returns total winning eth
    
//==============================================================================
//     _ _  _  _|. |`. _  _ _  .
//    | | |(_)(_||~|~|(/_| _\  .  (these are safety checks)
//==============================================================================
    /**
     * @dev used to make sure no one can interact with contract until it has
     * been activated.
     */
    modifier isActivated() {
        require(activated_ == true, "it's not ready yet");
        _;
    }

    /**
     * @dev prevents contracts from interacting with milfold,except constructor
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

    /**
     * @dev used to make sure the paid is sufficient to buy tickets.
     * @param _eth the eth you want pay for
     * @param _num the numbers you want to buy
     */
    modifier inSufficient(uint256 _eth, uint256[] memory _num) {
        uint256 totalTickets = _num.length;
        require(_eth >= totalTickets.mul(TICKET_VALUE), "insufficient to buy the very tickets");
        _;
    }
    
    /**
     * @dev prevents contracts from interacting with milfold,except constructor
     */
    modifier isEffectiveTime() {
        require(block.timestamp < round_[rID_].roundDeadline - entertainedTime, "not effective game time");
        _;
    }

    function getbalance() public view returns(uint256) {
        return address(this).balance;
    }
    
    function activate(uint256 startTime) public {
        // can only be ran once
        require(activated_ == false, "MilFold already activated");

        // activate the contract
        activated_ = true;

        // lets start first round
        rID_ = 1;
        round_[rID_].roundDeadline = startTime + rndMax_;
        round_[rID_].state = Mildatasets.RoundState.STARTED;
    }

    /**
     * @dev direct buy nums with pay eth in express way
     * @param _affID the id of the player who gets the affiliate fee
     * @param _nums which nums you buy, less than 10
     */
    function expressBuyNums(uint256 _affID, uint256[] memory _nums)
        public
        isActivated()
        isHuman()
        inSufficient(msg.value, _nums)
        isEffectiveTime()
        payable
    {
        buyCore(msg.sender, _affID, msg.value);
        
        Mildatasets.PlayerRound storage _playerRound = round_[rID_].playerRound[msg.sender];
        for (uint256 i = 0; i < _nums.length; i++) {
            _playerRound.tickMap[_nums[i]]++;
        }
        if (!_playerRound.exists) {
            round_[rID_].players.push(msg.sender);
            _playerRound.exists = true;
        }
    }

    function buyCore(address _addr, uint256 _affID, uint256 _eth)
        private
    {
        /**
         * 5% transfer to foundation
         * 75% transfer to pot
         * 20% transfer to millionaire, 15% use to convert MFCoin and 5% use to genAndAff
         */
        // transfer 5% to foundation
        uint256 foundFee = _eth.div(20);
        payable(fundAddr_).transfer(foundFee);

        // transfer 20%(15% use to convert MFCoin and 5% use to genAndAff) amount to millionaire
        uint256 milFee = _eth.div(5);
        uint256 mfBuy = _eth.mul(15).div(100);

        millionaire_.gameBuyMfAndAff{value:milFee}(_addr, _affID, mfBuy);

        round_[rID_].pot = round_[rID_].pot.add(_eth.sub(milFee).sub(foundFee));
    }

    /**
     * @dev claim the winner identified by the given player's address
     */
    function drawGame(string memory btcBlockHash, uint256 drawCode, uint256[3] memory winNums)
        public
        isActivated()
        onlyDevs()
    {
        require(block.timestamp > round_[rID_].roundDeadline, "the game is not over");
        require(drawCode < 1000, "invalid drawCode");
        require(winNums.length == 3, "invalid winNums");
		uint256 leftPot = round_[rID_].pot.div(10);  //10% for next round
		uint256 llID_ = rID_ - 1;
		
		uint256 winPot = round_[rID_].pot.mul(3).div(10);
		if (winNums[0] == 0) {
			leftPot = leftPot.add(winPot);
		} else {
		    round_[rID_].win1.totalNum = winNums[0];
		    round_[rID_].win1.winPot = winPot;
		}
		if (winNums[1] == 0) {
			leftPot = leftPot.add(winPot);
		} else {
		    round_[rID_].win2.totalNum = winNums[1];
		    round_[rID_].win2.winPot = winPot;
		}
		if (winNums[2] == 0) {
			leftPot = leftPot.add(winPot);
		} else {
		    round_[rID_].win3.totalNum = winNums[2];
		    round_[rID_].win3.winPot = winPot;
		}
		
        round_[rID_].state = Mildatasets.RoundState.STOPPED;
        round_[rID_].drawCode = drawCode;
        round_[rID_].drawBlockHash = btcBlockHash;

        rID_ = rID_ + 1;

        // migrate last round pot to this round util last round draw
        round_[rID_].state = Mildatasets.RoundState.STARTED;
        round_[rID_].roundDeadline = round_[rID_ - 1].roundDeadline + rndMax_;
		if (llID_ > 0 && ((round_[llID_].win1.winPot.add(round_[llID_].win2.winPot).add(round_[llID_].win3.winPot)) > round_[llID_].rewardPot)) {
			round_[rID_].pot = round_[llID_].win1.winPot.add(round_[llID_].win2.winPot).add(round_[llID_].win3.winPot).sub(round_[llID_].rewardPot).add(leftPot);
		} else {
			round_[rID_].pot = leftPot;
		}
    }
	
    /**
     * @dev claim the winner identified by the given player's address
     * @param _addr player's address
     */
    function rewardWinner(address _addr, uint256[] memory _rWinnerNum)
        public
        isActivated()
        isHuman()
    {
		uint256 lID_ = rID_ - 1;
		Mildatasets.PlayerRound storage playerRound = round_[lID_].playerRound[_addr];
		
        require(lID_ > 0 && round_[lID_].state == Mildatasets.RoundState.STOPPED, "it's not time for assignWinner");
        require(!playerRound.assign, "winner already reward");
        require(_rWinnerNum.length > 0, "winner number not empty");
		
		uint256 userTotalWin = 0;
		uint256 userWinNum1 = 0;
		uint256 userWinNum2 = 0;
		uint256 userWinNum3 = 0;
		for (uint256 i = 0; i< _rWinnerNum.length; i++) {
		    require(playerRound.tickMap[_rWinnerNum[i]] > 0, "not you tickets");
		    if (_rWinnerNum[i] == round_[lID_].drawCode) {
		        userWinNum1 += playerRound.tickMap[_rWinnerNum[i]];
            } else if (checkWin2(_rWinnerNum[i], round_[lID_].drawCode)) {
		        userWinNum2 += playerRound.tickMap[_rWinnerNum[i]];
            } else if (checkWin3(_rWinnerNum[i], round_[lID_].drawCode)) {
		        userWinNum3 += playerRound.tickMap[_rWinnerNum[i]];
            }
		}
		if (userWinNum1 > 0) {
		    round_[lID_].win1.winners.push(msg.sender);
		    userTotalWin += round_[lID_].win1.winPot.mul(userWinNum1).div(round_[lID_].win1.totalNum);
		}
		if (userWinNum2 > 0) {
		    round_[lID_].win2.winners.push(msg.sender);
		    userTotalWin += round_[lID_].win2.winPot.mul(userWinNum2).div(round_[lID_].win2.totalNum);
		}
		if (userWinNum3 > 0) {
		    round_[lID_].win3.winners.push(msg.sender);
		    userTotalWin += round_[lID_].win3.winPot.mul(userWinNum3).div(round_[lID_].win3.totalNum);
		}
		
		playerRound.assign = true;
		round_[lID_].rewardPot = round_[lID_].rewardPot.add(userTotalWin);
		playerWinTotal_[_addr] = playerWinTotal_[_addr].add(userTotalWin);
		payable(_addr).transfer(userTotalWin);
		emit onPlayerReward(_addr, lID_, userTotalWin, userWinNum1, userWinNum2, userWinNum3);
    }
	
	function checkWin2(uint256 userCode, uint256 drawCode)
	    private
        pure
        returns(bool)
    {
		uint256 drawNum1 = drawCode / 100;
		uint256 drawNum2 = (drawCode - drawNum1 * 100) / 10;
		uint256 drawNum3 = drawCode - drawNum1 * 100 - drawNum2 * 10;
		
		uint256 userNum1 = userCode / 100;
		uint256 userNum2 = (userCode - userNum1 * 100) / 10;
		uint256 userNum3 = userCode - userNum1 * 100 - userNum2 * 10;
		return (drawNum1 == userNum1 && drawNum2 == userNum2 && drawNum3 != userNum3) || 
				(drawNum1 == userNum1 && drawNum2 != userNum2 && drawNum3 == userNum3) || 
				(drawNum1 != userNum1 && drawNum2 == userNum2 && drawNum3 == userNum3);
	}
	
	function checkWin3(uint256 userCode, uint256 drawCode)
	    private
        pure
        returns(bool)
    {
		if (drawCode < 100) {
			return userCode < 100;
		}
		return (drawCode / 100) == (userCode / 100);
	}
	
    /**
     * @dev return players's total winning eth
     * @param _addr player's address
     * @return player's total tickets
     */
    function getPlayerTotalWin(address _addr)
        public
        view
        returns(uint256)
    {
        return (playerWinTotal_[_addr]);
    }

    /**
     * @dev return players's total winning eth
     * @param _addr player's address
     * @return player's is win current round
     * @return player's has reward current round
     */
    function checkPlayerWinner(address _addr)
        public
        view
        returns(bool, bool, uint256[] memory winTicks)
    {
        uint256 lID_ = rID_ - 1;
        uint256 winNum1 = 0;
        uint256 winNum2 = 0;
        uint256 winNum3 = 0;
        uint256[] memory winNum = new uint256[](1000);
        uint256 index = 0;
        for (uint256 i = 0; i < 1000; i++) {
            if (round_[lID_].playerRound[_addr].tickMap[i] > 0) {
                if (i == round_[lID_].drawCode) {
                    winNum1 += round_[lID_].playerRound[_addr].tickMap[i];
                    winNum[index++] = i;
                } else if (checkWin2(i, round_[lID_].drawCode)) {
                    winNum2 += round_[lID_].playerRound[_addr].tickMap[i];
                    winNum[index++] = i;
                } else if (checkWin3(i, round_[lID_].drawCode)) {
                    winNum3 += round_[lID_].playerRound[_addr].tickMap[i];
                    winNum[index++] = i;
                }
            }
        }
        
        winTicks = new uint256[](index);
        for (uint256 j = 0; j < index; j++) {
            winTicks[j] = winNum[j];
        }
        return ((winNum1 > 0 || winNum2 > 0 || winNum3 > 0), round_[lID_].playerRound[_addr].assign, winTicks);
    }

    /**
     * @dev return numbers in the round
     * @param _rid round id
     * @param _addr player's address
     * @return userTickets player's numbers
     * @return userNotes player's num notes
     */
    function getPlayerRoundNums(uint256 _rid, address _addr)
        public
        view
        returns(uint256[] memory userTickets, uint256[] memory userNotes)
    {
        // mapping(uint256 => uint256) memory uTickMap = round_[_rid].playerRound[_addr].tickMap;
        uint256[] memory tmpTicks = new uint256[](1000);
        uint256 index = 0;
        for (uint256 i = 0; i < 1000; i++) {
            if (round_[_rid].playerRound[_addr].tickMap[i] > 0) {
                tmpTicks[index++] = i;
            }
        }
        userTickets = new uint256[](index);
        userNotes = new uint256[](index);
        for (uint256 j = 0; j < index; j++) {
            userTickets[j] = tmpTicks[j];
            userNotes[j] = round_[_rid].playerRound[_addr].tickMap[tmpTicks[j]];
        }
        return (userTickets, userNotes);
    }

    /**
     * @dev return current round information
     * @return current round id
     * @return current round end time
     * @return current round pot
     * @return last round pot
     */
    function getCurrentRoundInfo()
        public
        view
        returns(uint256, uint256, uint256, uint256)
    {
        return (
            rID_,
            round_[rID_].roundDeadline,
            round_[rID_].pot,
            round_[rID_ - 1].drawCode
        );
    }

    /**
     * @dev return round players
     */
    function getRoundPlayers(uint256 _rid)
        public
        view
        returns(address[] memory)
    {
        return round_[_rid].players;
    }

    /**
     * @dev return history round information
     * @param _rid round id
     * @return btcBlockHash draw blockhash
     * @return items include as following
     *  round end time
     *  draw code
     *  round pot
     *  left pot
     *  totalNum1
     *  avgAmount1
     *  totalNum2
     *  avgAmount2
     *  totalNum3
     *  avgAmount3
     * @return winner1 address
     * @return winner2 address
     * @return winner3 address
     */
    function getHistoryRoundInfo(uint256 _rid)
        public
        view
        returns(string memory, uint256[] memory items, address[] memory, address[] memory, address[] memory)
    {
        items = new uint256[](10);
        items[0] = round_[_rid].roundDeadline;
        items[1] = round_[_rid].drawCode;
        items[2] = round_[_rid].pot;
        if (_rid >= rID_) {
            items[3] = 0;
        } else if (_rid + 1 == rID_) {
            items[3] = round_[_rid].pot.sub(round_[_rid].win1.winPot + round_[_rid].win2.winPot + round_[_rid].win3.winPot);
        } else {
            items[3] = round_[_rid].pot.sub(round_[_rid].rewardPot);
        }
        items[4] = round_[_rid].win1.totalNum;
        if (round_[_rid].win1.totalNum > 0) {
            items[5] = round_[_rid].win1.winPot.div(round_[_rid].win1.totalNum);
        } else {
            items[5] = 0;
        }
        items[6] = round_[_rid].win2.totalNum;
        if (round_[_rid].win2.totalNum > 0) {
            items[7] = round_[_rid].win2.winPot.div(round_[_rid].win2.totalNum);
        } else {
            items[7] = 0;
        }
        items[8] = round_[_rid].win3.totalNum;
        if (round_[_rid].win3.totalNum > 0) {
            items[9] = round_[_rid].win3.winPot.div(round_[_rid].win3.totalNum);
        } else {
            items[9] = 0;
        }
        
        return (round_[_rid].drawBlockHash, items, round_[_rid].win1.winners, round_[_rid].win2.winners, round_[_rid].win3.winners);
    }

	// function kill() onlyDevs public {
    //    selfdestruct(msg.sender); // 销毁合约
    // }
}

//==============================================================================
//   __|_ _    __|_ _  .
//  _\ | | |_|(_ | _\  .
//==============================================================================
library Mildatasets {

    // between `DRAWN' and `ASSIGNED', someone need to claim winners.
    enum RoundState {
        UNKNOWN,        // aim to differ from normal states
        STARTED,        // start current round
        STOPPED         // stop current round
    }

    struct Player {
        uint256 playerID;       // Player id(use to affiliate other player)
        uint256 affTotal;       // affiliate total vault
        uint256 laff;           // last affiliate id used
    }

    struct Round {
        uint256                             roundDeadline;      // deadline to end round
        uint256                             pot;                // pot
        uint256                             rewardPot;          // already reward
        RoundState                          state;              // round state
        string                              drawBlockHash;      // draw Bitcoin blockhash
        uint256                             drawCode;           // draw code
        Winning                             win1;               // win1 info
        Winning                             win2;               // win2 info
        Winning                             win3;               // win3 info
        mapping (address => PlayerRound)    playerRound;        // playerRound info
        address[]                           players;            // playerRound array
    }

    struct PlayerRound {
        uint256                         winnerNum1;             // winners' number 1
        uint256                         winnerNum2;             // winners' number 2
        uint256                         winnerNum3;             // winners' number 3
        bool                            assign;                 // player is assign reward
        bool                            exists;                 // exists
        mapping (uint256 => uint256)    tickMap;                // winners' is assign
    }

    struct Winning {
        uint256                         totalNum;           // total number
        uint256                         winPot;             // winning pot
        address[]                       winners;            // winners
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
        uint256 z = ((add(x,1)) / 2);
        y = x;
        while (z < y)
        {
            y = z;
            z = ((add((x / z),z)) / 2);
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
        return (mul(x,x));
    }

    /**
     * @dev x to the power of y
     */
    function pwr(uint256 x, uint256 y)
        internal
        pure
        returns (uint256)
    {
        if (x==0)
            return (0);
        else if (y==0)
            return (1);
        else
        {
            uint256 z = x;
            for (uint256 i=1; i < y; i++)
                z = mul(z,x);
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
