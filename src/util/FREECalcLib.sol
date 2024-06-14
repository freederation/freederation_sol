//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

import "./FREEcommon.sol";


struct StarIslandBondingCurve
{
    /// Island floor base price. It could vary depending of the planet bonding curve
    uint256 island_floor_price;

    /// Island percentaje factor for incrementing the base price taking the number of islands
    uint256 island_curve_price_rate;

    /// Grace periods earned by Star project
    uint32 star_prestige;

    /// Number of minted islands
    uint32 island_count;
}

library FREE_CalcLib
{
    uint256 constant FREE_PRESTIGE_ISLAND_DIVISOR = 1000;

    uint256 constant FREE_PRESTIGE_ISLAND_DIVISOR_P3 = FREE_PRESTIGE_ISLAND_DIVISOR * FREE_PRESTIGE_ISLAND_DIVISOR * FREE_PRESTIGE_ISLAND_DIVISOR;


    /**
     * Bonding curve for calculating the price of an Island depending of the emission rate.
     */
    function curve_floor_price(StarIslandBondingCurve memory starcurve) internal pure returns(uint256)
    {
        uint256 scaled_island = uint256(starcurve.island_count) * FREE_PRESTIGE_ISLAND_DIVISOR;
        uint256 scaled_curve_factor = scaled_island / uint256(starcurve.star_prestige);
        uint256 curve_rate_pow3 = starcurve.island_curve_price_rate * scaled_curve_factor * scaled_curve_factor * scaled_curve_factor;

        uint256 src_floor_price = starcurve.island_floor_price;
        /// in percentaje, needs to be divided by FREE_PERCENTAJE_FACTOR
        uint256 price_factor_scaled = src_floor_price * curve_rate_pow3;

        uint256 price_increment = price_factor_scaled / FREE_PRESTIGE_ISLAND_DIVISOR_P3;

        uint256 new_price_scaled = (src_floor_price * FREE_PERCENTAJE_FACTOR) + price_increment;

        // fix percentaje
        return new_price_scaled / FREE_PERCENTAJE_FACTOR;
    }
}