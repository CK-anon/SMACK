/* In C, just change cmath to math.h and std::ldexp to ldexp. */
#include <cmath>
#include <iostream>


double difficulty(const unsigned bits) {
  const unsigned exponent_diff  = 8 * (0x1D - ((bits >> 24) & 0xFF));
  const double significand = bits & 0xFFFFFF;
  return std::ldexp(0x00FFFF / significand, exponent_diff);
}

int main(){
  std::cout<<difficulty(0x1b15a845)<<std::endl;	
}
