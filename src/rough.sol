// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract EnhancedPredictionMarket is Ownable, ReentrancyGuard {
    struct Prediction {
        string description;
        uint256 endTime;
        uint256 yesShares;
        uint256 noShares;
        uint256 totalYesVotes;
        uint256 totalNoVotes;
        bool isResolved;
        bool outcome;
        uint256 targetPrice;
        address priceFeed;
    }

    Prediction[] public predictions;
    mapping(uint256 => mapping(address => uint256)) public userYesShares;
    mapping(uint256 => mapping(address => uint256)) public userNoShares;

    uint256 public constant MIN_BET = 0.01 ether;
    uint256 public constant FEE_PERCENTAGE = 1; // 1% fee

    event PredictionCreated(uint256 indexed predictionId, string description, uint256 endTime, uint256 targetPrice, address priceFeed);
    event SharesPurchased(uint256 indexed predictionId, address user, bool isYes, uint256 amount, uint256 shares);
    event PredictionResolved(uint256 indexed predictionId, bool outcome, uint256 finalPrice);

    constructor() Ownable(msg.sender) {}

    function createPrediction(string memory _description, uint256 _duration, uint256 _targetPrice, address _priceFeed) external onlyOwner {
        require(_duration > 0, "Duration must be positive");
        require(_priceFeed != address(0), "Invalid price feed address");
        uint256 endTime = block.timestamp + _duration;
        predictions.push(Prediction(_description, endTime, 0, 0, 0, 0, false, false, _targetPrice, _priceFeed));
        emit PredictionCreated(predictions.length - 1, _description, endTime, _targetPrice, _priceFeed);
    }

    function purchaseShares(uint256 _predictionId, bool _isYes) external payable nonReentrant {
        require(msg.value >= MIN_BET, "Bet amount too low");
        Prediction storage prediction = predictions[_predictionId];
        require(block.timestamp < prediction.endTime, "Prediction has ended");
        require(!prediction.isResolved, "Prediction already resolved");

        uint256 fee = (msg.value * FEE_PERCENTAGE) / 100;
        uint256 betAmount = msg.value - fee;

        uint256 shares;
        if (_isYes) {
            shares = calculateShares(betAmount, prediction.yesShares, prediction.totalYesVotes);
            prediction.yesShares += shares;
            prediction.totalYesVotes += betAmount;
            userYesShares[_predictionId][msg.sender] += shares;
        } else {
            shares = calculateShares(betAmount, prediction.noShares, prediction.totalNoVotes);
            prediction.noShares += shares;
            prediction.totalNoVotes += betAmount;
            userNoShares[_predictionId][msg.sender] += shares;
        }

        emit SharesPurchased(_predictionId, msg.sender, _isYes, betAmount, shares);
    }

    function calculateShares(uint256 _amount, uint256 _currentShares, uint256 _totalVotes) private pure returns (uint256) {
        if (_totalVotes == 0) {
            return _amount;
        }
        return (_amount * _currentShares) / _totalVotes;
    }

    function resolvePrediction(uint256 _predictionId) external onlyOwner {
        Prediction storage prediction = predictions[_predictionId];
        require(block.timestamp >= prediction.endTime, "Prediction has not ended yet");
        require(!prediction.isResolved, "Prediction already resolved");

        uint256 currentPrice = getCurrentPrice(_predictionId);

        prediction.isResolved = true;
        prediction.outcome = currentPrice >= prediction.targetPrice;

        emit PredictionResolved(_predictionId, prediction.outcome, currentPrice);
    }

    function getCurrentPrice(uint256 _predictionId) public view returns (uint256) {
        Prediction storage prediction = predictions[_predictionId];
        require(prediction.priceFeed != address(0), "Invalid prediction ID");
        
        AggregatorV3Interface priceFeed = AggregatorV3Interface(prediction.priceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function claimRewards(uint256 _predictionId) external nonReentrant {
        Prediction storage prediction = predictions[_predictionId];
        require(prediction.isResolved, "Prediction not resolved yet");

        uint256 userShares = prediction.outcome ? userYesShares[_predictionId][msg.sender] : userNoShares[_predictionId][msg.sender];
        require(userShares > 0, "No shares to claim");

        uint256 totalShares = prediction.outcome ? prediction.yesShares : prediction.noShares;
        uint256 totalPot = prediction.totalYesVotes + prediction.totalNoVotes;

        uint256 reward = (userShares * totalPot) / totalShares;

        if (prediction.outcome) {
            userYesShares[_predictionId][msg.sender] = 0;
        } else {
            userNoShares[_predictionId][msg.sender] = 0;
        }

        payable(msg.sender).transfer(reward);
    }

    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
    }

    function getPredictionCount() external view returns (uint256) {
        return predictions.length;
    }

    function getPrediction(uint256 _predictionId) external view returns (Prediction memory) {
        return predictions[_predictionId];
    }

    function getUserShares(uint256 _predictionId, address _user) external view returns (uint256 yesShares, uint256 noShares) {
        return (userYesShares[_predictionId][_user], userNoShares[_predictionId][_user]);
    }
}