# wilson_ci.R
#
# Wilson score confidence interval for a binomial proportion.
# Used for decile bad-rate intervals where each decile is treated
# independently. These are screening intervals for triage, not
# hypothesis tests -- comparing all nine adjacent pairs is nine
# comparisons and will occasionally show a spurious gap.

wilson_ci <- function(k, n, conf = 0.95) {
  z <- qnorm(1 - (1 - conf) / 2)
  p <- k / n
  d <- 1 + z^2 / n
  center <- (p + z^2 / (2 * n)) / d
  half <- z / d * sqrt(p * (1 - p) / n + z^2 / (4 * n^2))
  lower <- pmax(0, center - half)
  upper <- pmin(1, center + half)
  list(lower = lower, upper = upper)
}
