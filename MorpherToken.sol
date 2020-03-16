pragma solidity 0.5.16;

import "./Context.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./MorpherStateBeta.sol";


/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20Mintable}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract MorpherToken is Context, IERC20, Ownable {

    MorpherStateBeta state;
    using SafeMath for uint256;

    string public constant name     = "Morpher";
    string public constant symbol   = "MPH";
    uint8  public constant decimals = 18;

    modifier onlyState {
        require(msg.sender == address(state), "Caller must be MorpherState contract.");
        _;
    }

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    constructor(address _stateAddress) public {
        state = MorpherStateBeta(_stateAddress);
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view returns (uint256) {
        return state.totalSupply();
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address _account) public view returns (uint256) {
        return state.balanceOf(_account);
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address _recipient, uint256 _amount) public returns (bool) {
        _transfer(_msgSender(), _recipient, _amount);
        return true;
    }

   /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address _owner, address _spender) public view returns (uint256) {
        return state.getAllowance(_owner, _spender);
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address _spender, uint256 _amount) public returns (bool) {
        _approve(_msgSender(), _spender, _amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20};
     *
     * Requirements:
     * - `_sender` and `_recipient` cannot be the zero address.
     * - `_sender` must have a balance of at least `amount`.
     * - the caller must have allowance for `_sender`'s tokens of at least
     * `amount`.
     */
    function transferFrom(address _sender, address _recipient, uint256 amount) public returns (bool) {
        _transfer(_sender, _recipient, amount);
        _approve(_sender, _msgSender(), state.getAllowance(_sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `_spender` cannot be the zero address.
     */
    function increaseAllowance(address _spender, uint256 _addedValue) public returns (bool) {
        // _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        state.setAllowance(_msgSender(), _spender, state.getAllowance(_msgSender(), _spender).add(_addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address _spender, uint256 _subtractedValue) public returns (bool) {
        state.setAllowance(_msgSender(), _spender, state.getAllowance(_msgSender(), _spender).sub(_subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function stateMint(address _account, uint256 _amount) public onlyState {
        _mint(_account, _amount);
    }

     function stateBurn(address _account, uint256 _amount) public onlyState {
        _burn(_account, _amount);
    }

     function burn(uint256 _amount) public {
        _burn(_msgSender(), _amount);
    }

     /**
     * @dev Moves tokens `_amount` from `sender` to `_recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `_sender` cannot be the zero address.
     * - `_recipient` cannot be the zero address.
     * - `_sender` must have a balance of at least `_amount`.
     */
    function _transfer(address _sender, address _recipient, uint256 _amount) internal {
        require(_sender != address(0), "ERC20: transfer from the zero address");
        require(_recipient != address(0), "ERC20: transfer to the zero address");
        require(state.balanceOf(_sender) >= _amount, "ERC20: transfer amount exceeds balance");
        state.subBalance(_sender, _amount);
        state.addBalance(_sender, _amount);
        emit Transfer(_sender, _recipient, _amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "ERC20: mint to the zero address");
        state.addBalance(_account, _amount);
        emit Transfer(address(0), _account, _amount);
    }

    /**
     * @dev Destroys `_amount` tokens from `_account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `_account` cannot be the zero address.
     * - `_account` must have at least `_amount` tokens.
     */
    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        state.subBalance(account, amount);
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `_amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This is internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 _amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        state.setAllowance(owner, spender, _amount);
        emit Approval(owner, spender, _amount);
    }

    /**
     * @dev Destroys `_amount` tokens from `account`.`_amount` is then deducted
     * from the caller's allowance.
     *
     * See {_burn} and {_approve}.
     */
    function _burnFrom(address account, uint256 _amount) internal {
        _burn(account, _amount);
        state.setAllowance(account, _msgSender(), state.getAllowance(account, _msgSender()).sub(_amount));
    }
    
    // ------------------------------------------------------------------------
    // Don't accept ETH
    // ------------------------------------------------------------------------
    function () external payable {
        revert("You can't deposit Ether here");
    }

    // ------------------------------------------------------------------------
    // Owner can transfer out any accidentally sent ERC20 tokens
    // ------------------------------------------------------------------------
    function transferAnyERC20Token(address _tokenAddress, uint256 _tokens) public onlyOwner returns (bool _success) {
        return IERC20(_tokenAddress).transfer(owner(), _tokens);
    }
}