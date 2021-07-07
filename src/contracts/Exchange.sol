pragma solidity ^0.5.0;

import "./Token.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

/*
    Set the fee account to collect exchange fees
    Set fee percentage
    Deposit Ether
    Withdraw Ether
    Deposit tokens
    Withdraw tokens
    Check balances
    Make order
    Fill order
    Cancel order
    Charge fees
*/

contract Exchange {
    using SafeMath for uint;

    // Variables
    address public feeAccount; // the account that receives exchange fees
    uint256 public feePercent; // the fee percentage
    address constant ETHER = address(0); // Store Ether in tokens mapping with blank address
    mapping (address => mapping (address => uint256)) public tokens; // Token address to user address => number of tokens by user
    // Model the order
    struct _Order {
        uint256 id;
        address user;
        address tokenGet;
        uint256 amountGet;
        address tokenGive;
        uint256 amountGive;
        uint256 timestamp;
    }
    // Store the order: id to struct, public so free read
    mapping(uint256 => _Order) public orders;
    uint256 public orderCount; // Counter cash to track order counts starts as 0
    mapping(uint256 => bool) public orderCancelled; // Cancelled orders mapping
    mapping(uint256 => bool) public orderFilled; // Filled orders mapping

    // Events
    event Deposit(address token, address user, uint256 amount, uint256 balance);
    event Withdraw(address token, address user, uint256 amount, uint256 balance);
    event Order(
        uint256 id, 
        address user, 
        address tokenGet, 
        uint256 amountGet, 
        address tokenGive, 
        uint256 amountGive, 
        uint256 timestamp
    );
    event Cancel(
        uint256 id, 
        address user, 
        address tokenGet, 
        uint256 amountGet, 
        address tokenGive, 
        uint256 amountGive, 
        uint256 timestamp
    );
     event Trade(
        uint256 id, 
        address user, 
        address tokenGet, 
        uint256 amountGet, 
        address tokenGive, 
        uint256 amountGive,
        address userFill,
        uint256 timestamp
    );

    constructor (address _feeAccount, uint256 _feePercent) public {
        feeAccount = _feeAccount;
        feePercent = _feePercent;
    }

    // Fallback: revert if Ether is sent to this contract by mistake
    function() external {
        revert();
    }

    // Deposit Ether
    function depositEther() payable public {
        tokens[ETHER][msg.sender] = tokens[ETHER][msg.sender].add(msg.value);
        emit Deposit(ETHER, msg.sender, msg.value, tokens[ETHER][msg.sender]);
    }

    // Withdraw Ether
    function withdrawEther(uint256 _amount) public {
        require(tokens[ETHER][msg.sender] >= _amount);
        tokens[ETHER][msg.sender] = tokens[ETHER][msg.sender].sub(_amount);
        // Transfer Ether back to sender/user
        msg.sender.transfer(_amount);
        emit Withdraw(ETHER, msg.sender, _amount, tokens[ETHER][msg.sender]);
    }

    /* 
        Which token? Any ERC20.
        How much?
        Send tokens to this contract/this exchange (approve this contract on behalf to transfer tokens)
        Manage deposit - update balance
        Emit event
    */
    function depositToken(address _token, uint256 _amount) public {
        // Don't allow Ether deposits
        require(_token != ETHER);
        // Transfer from has to always work
        require(Token(_token).transferFrom(msg.sender, address(this), _amount));
        tokens[_token][msg.sender] = tokens[_token][msg.sender].add(_amount);
        emit Deposit(_token, msg.sender, _amount, tokens[_token][msg.sender]);
    }

    // Withdraw Token
    function withdrawToken(address _token, uint256 _amount) public {
         // Don't allow Ether withrawals
        require(_token != ETHER);
        require(tokens[_token][msg.sender] >= _amount);
        tokens[_token][msg.sender] = tokens[_token][msg.sender].sub(_amount);
        // Transfer tokens back to sender/user by using transfer function
        require(Token(_token).transfer(msg.sender, _amount));
        emit Withdraw(_token, msg.sender, _amount, tokens[_token][msg.sender]);
    }

    // Check balance
    function balanceOf(address _token, address _user) public view returns (uint256) {
        return tokens[_token][_user];
    }

    // Make order
    function makeOrder(address _tokenGet, uint256 _amountGet, address _tokenGive, uint256 _amountGive) public {
        orderCount = orderCount.add(1);
        // Model an order and store
        orders[orderCount] = _Order(orderCount, msg.sender, _tokenGet, _amountGet, _tokenGive, _amountGive, now);
        emit Order(orderCount, msg.sender, _tokenGet, _amountGet, _tokenGive, _amountGive, now);
    }

    // Cancel order
    function cancelOrder(uint256 _id) public {
        _Order storage _order = orders[_id]; // fetch order from storage/blockchain to local var
        // Must be my/sender's order
        require(address(_order.user) == msg.sender);
        // Must be a valid oder 
        require(_order.id == _id);
        orderCancelled[_id] = true;
        emit Cancel(_order.id, msg.sender, _order.tokenGet, _order.amountGet, _order.tokenGive, _order.amountGive, now);
    }

    /* 
        Fill order:
        Fetch the order
        Execute trade
        Charge fees
        Emit trade event
        Mark order as filled
    */
    function fillOrder(uint256 _id) public {
        // First check valid order id
        require(_id > 0 && _id <= orderCount);
        // Make sure order is not already filled or cancelled
        require(!orderFilled[_id]);
        require(!orderCancelled[_id]);
         _Order storage _order = orders[_id];
         _trade(_order.id, _order.user, _order.tokenGet, _order.amountGet, _order.tokenGive, _order.amountGive);
        orderFilled[_order.id] = true;
    }

    function _trade(uint256 _orderId, address _user, address _tokenGet, uint256 _amountGet, address _tokenGive, uint256 _amountGive) internal {
        // Charge fees
        // Fee paid by user that fills the order, a.k.a msg.sender so charge fee percent from _amountGet tokens.
        // Fee deducted from _amountGet
        uint256 _feeAmount = _amountGet.mul(feePercent).div(100);
        // Take fees tokens in our fee account
        tokens[_tokenGet][feeAccount] = tokens[_tokenGet][feeAccount].add(_feeAmount);

        // Execute trade: To execute the order msg.sender must have tokens + fees
        tokens[_tokenGet][msg.sender] = tokens[_tokenGet][msg.sender].sub(_amountGet.add(_feeAmount));
        tokens[_tokenGet][_user] = tokens[_tokenGet][_user].add(_amountGet);
        tokens[_tokenGive][_user] = tokens[_tokenGive][_user].sub(_amountGive);
        tokens[_tokenGive][msg.sender] = tokens[_tokenGive][msg.sender].add(_amountGive);

        // Emit trade event
        emit Trade(_orderId, _user, _tokenGet, _amountGet, _tokenGive, _amountGive, msg.sender, now);
    }
}