# cython: profile=False, boundscheck=True, wraparound=False
# TODO Turn off boundscheck

from libc cimport math
import numpy as np
cimport numpy as np
np.seterr(all='raise')
import collections

class Hyp:
    def __init__(self, pb, pnb, nc):
        self.p_b = pb
        self.p_nb = pnb
        self.n_c = nc

def init_hyp():
    hyp = Hyp(float('-inf'), float('-inf'), 0)
    return hyp

# Add 2 probabilities in log space together and take log
# Used for p_b + p_nb
cdef double exp_sum_log(double a, double b):
    cdef double psum = math.exp(a) + math.exp(b)
    if psum == 0.0:
        return float('-inf')
    return math.log(psum)

cdef double lm_placeholder(c, seq):
    return 0.0

def decode_bg_clm(double[::1,:] probs not None, lm, unsigned int beam=40, double alpha=1.0, double beta=0.0):
    cdef unsigned int N = probs.shape[0]
    cdef unsigned int T = probs.shape[1]
    cdef unsigned int t, k, l, y_e
    cdef double collapse_prob, p_tot

    # Need beta to be in scope
    pref_prob = lambda x: exp_sum_log(x[1].p_nb, x[1].p_b) + beta * x[1].n_c

    # Loop over time
    for t in xrange(T):
        #print '%d/%d' % (t, T)

        # Beam cutoff
        if t == 0:
            B_hat = dict()
            # Initial empty prefix
            B_hat[()] = Hyp(0.0, float('-inf'), 0)
        else:
            B_hat = dict(sorted(B.iteritems(), key=pref_prob, reverse=True)[:beam])
        B = collections.defaultdict(init_hyp)

        # Loop over prefixes
        for prefix, hyp in B_hat.iteritems():
            l = len(prefix)
            p_tot = exp_sum_log(hyp.p_b, hyp.p_nb)

            new_hyp = B[prefix]
            # Handle collapsing
            if l > 0:
                new_hyp.p_nb = hyp.p_nb + probs[prefix[l-1], t]
                prev_pref = prefix[:l-1]
                if prev_pref in B_hat:
                    prev_hyp = B_hat[prev_pref]

                    y_e = prefix[l-1]
                    # P(y[-1], y[:-1], t) in Graves paper
                    collapse_prob = probs[y_e, t] + lm_placeholder(y_e, prev_pref)
                    if l > 1 and y_e == prefix[l-2]:
                        collapse_prob += prev_hyp.p_b
                    else:
                        collapse_prob += exp_sum_log(prev_hyp.p_b, prev_hyp.p_nb)

                    new_hyp.p_nb = exp_sum_log(new_hyp.p_nb, collapse_prob)

            # Handle blank extension
            new_hyp.p_b = p_tot + probs[0, t]

            # Handle other extensions
            # Loop over characters excluding blank
            for k in xrange(1, N):
                ext_prefix = tuple(list(prefix) + [k])
                ext_hyp = Hyp(float('-inf'), 0.0, hyp.n_c + 1)

                # P(k, y, t) in Graves paper
                ext_hyp.p_nb = probs[k, t] + lm_placeholder(k, prefix)
                if l > 0 and k == prefix[l-1]:
                    ext_hyp.p_nb += hyp.p_b
                else:
                    ext_hyp.p_nb += p_tot

                B[ext_prefix] = ext_hyp

    B_final = sorted(B.iteritems(), key=pref_prob, reverse=True)
    return list(B_final[0][0]), pref_prob(B_final[0])
