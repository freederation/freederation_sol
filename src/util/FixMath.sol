//SPDX-License-Identifier:MIT
pragma solidity >=0.8.8;

// VRF Fix point
uint32 constant FREE_FIX64_FRACBITS = 32;
int64 constant FREE_FIX64_NAN = -0x7fffffffffffffff;

library Fix64Math {
    function mul(int64 val0, int64 val1) internal pure returns (int64) {
        int128 bignum = int128(val0) * int128(val1);
        return int64(bignum >> FREE_FIX64_FRACBITS);
    }

    function i32_to_fix(int32 val0) internal pure returns (int64) {
        return int64(val0) << FREE_FIX64_FRACBITS;
    }

    function div(int64 value, int64 divisor) internal pure returns (int64) {
        if (divisor == int64(0)) {
            return FREE_FIX64_NAN;
        }

        int128 bignum = int128(value);
        int128 retval = (bignum << uint128(FREE_FIX64_FRACBITS)) / int128(divisor);
        return int64(retval);
    }
}
