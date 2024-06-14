//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

uint256 constant FREE_PERCENTAJE_FACTOR = 10000;

uint256 constant FREE_UPPER_TOKEN_MASK_BIT_COUNT = 192;

// Also is the token mask
uint256 constant FREE_MAX_TOKEN_VALUE = (uint256(1) << FREE_UPPER_TOKEN_MASK_BIT_COUNT) - uint256(1);

uint256 constant FREE_UPPER_TOKEN_MASK = ~FREE_MAX_TOKEN_VALUE;

uint32 constant INVALID_INDEX32 = 0xffffffff;

uint64 constant INVALID_INDEX64 = 0xffffffffffffffff;

uint256 constant FREE_DEFAULT_TOKEN_ID = 1; // A reference value that is not used and could indicates a null.

uint256 constant FREE_MAX_INSURANCE_PERCENTAJE = 5000;//50%
uint256 constant FREE_MAX_INSURANCE_RISK_THRESHOLD = 5000;//50%
uint256 constant FREE_MIN_INSURANCE_RISK_THRESHOLD = 100;//1%


// Prestige Grace Periods parameters
//
uint32 constant FREE_ACCREDITED_AGE_INIT = 3;
uint32 constant FREE_PIONEER_SPONSOR_PLANET_CURVE = 9;
uint32 constant FREE_AGE_FOR_SPONSORSHIP = 9;
//


// Star promotion status
//
int16 constant FREE_STATUS_UNACCREDITED = 0;
int16 constant FREE_STATUS_PROMOTING = -1;
int16 constant FREE_STATUS_GUILTY = -2;
int16 constant FREE_STATUS_REDEMPTION = -3;
int16 constant FREE_STATUS_ACCREDITED = 1;
int16 constant FREE_STATUS_PARDONED = 2;
int16 constant FREE_STATUS_SPONSORSHIP_BONUS = 4;
int16 constant FREE_STATUS_HONORABLE_BONUS = 8;
int16 constant FREE_STATUS_HONORABLE_SPONSOR_BONUS = 12;
int16 constant FREE_STATUS_SPONSORSHIP_EXTRA_BONUS = 16;
//

// Token types
//
uint256 constant FREE_NUCLEUS_TOKEN = 1;
uint256 constant FREE_STAR_TOKEN = 2;
uint256 constant FREE_PLANET_TOKEN = 3;
uint256 constant FREE_ISLAND_TOKEN = 4;
uint256 constant FREE_RING_TOKEN = 5;
uint256 constant FREE_PUZZLE_TOKEN = 6;
uint256 constant FREE_ARCHANGEL_TOKEN = 7;
///

bytes32 constant FREE_NULL_NAME = bytes32(0);

function FREE_PERCENTAJE(uint256 _price, uint256 _percentaje) pure returns(uint256)
{
    return (_price * _percentaje) /  FREE_PERCENTAJE_FACTOR;
}


function FREE_ADDRtoU256(address _address)  pure returns(uint256)
{
    return uint256(uint160(_address));
}


function FREE_U256toADDR(uint256 _address)  pure returns(address)
{
    return address(uint160(_address));
}

function FREE_IsNullName(bytes32 strname) pure returns(bool)
{
    return strname == FREE_NULL_NAME;
}

// common errors
error ErrDAO_InvalidParams();

error ErrDAO_UnauthorizedAccess();