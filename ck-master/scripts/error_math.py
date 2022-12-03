import scipy.special


def compute_prob(n,p,k):
  su = 0
  for i in range(k):
    su += ((1-p) ** (n-i)) * (p ** i) * scipy.special.binom(n,i)
  return 1 - su


r_asic = 13 * (10 ** 12)
r_cpu = 67 * (10 ** 6)


r_cpu *= 1000

p = 1/r_asic
tau = 10
tau2 = 62
k = 1
k2 = 5

n_asic = r_asic * tau
n_cpu = r_cpu * tau

n_asic_con = r_asic * tau2
n_cpu_con = r_cpu * tau2

# Sequential
print(compute_prob(n_asic, p, k))
one_round = compute_prob(n_cpu, p, k)
print(one_round)
print((one_round) ** (k2))  # Done for k2 rounds

print()

# Concurrent
print(compute_prob(n_asic_con, p, k2))
all_round = compute_prob(n_cpu_con, p, k2)
print(all_round)