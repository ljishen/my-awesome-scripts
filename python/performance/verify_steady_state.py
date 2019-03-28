#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# MIT License
#
# Copyright (c) 2018 Jianshen Liu
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


"""Script to verify if the input values satisfy the criteria of steady state.

Definition of Steady State:
(https://www.snia.org/sites/default/files/technical_work/PTS/SSS_PTS_2.0.1.pdf)

Steady State: A device is said to be in Steady State when, for the dependent
variable (y) being tracked:
    a) Range(y) is less than 10% of Ave(y): Max(y)-Min(y) within the
       Measurement Window is no more than 20% of the Ave(y) within the
       Measurement Window; and
    b) Slope(y) is less than 10%: Max(y)-Min(y), where Max(y) and Min(y) are
       the maximum and minimum values on the best linear curve fit of the
       y-values within the Measurement Window, is within 10% of Ave(y) value
       within the Measurement Window.

Note that the length of measurement window is 5 according to the PTS
(e.g. Throughput Test on page 37).


Usage:
    verify_ss.py LIST WINDOW_SIZE

LIST        the values in list
WINDOW_SIZE the number of last values in LIST used for steady state detection

"""

import sys
import ast

import numpy as np


EXCURSION_THRESHOLD = 0.1


def main():
    """Perform verification.

    Exit status:
        1: Do not satisfy the criteria of steady state.
        0: The input values satisfy the criteria of steady state.

    """
    values = ast.literal_eval(sys.argv[1])
    measurement_window_size = int(sys.argv[2])

    if len(values) < measurement_window_size:
        print('Not enough input values (< %d): %s'
              % (measurement_window_size, values))
        exit(1)

    values_in_window = values[-1 * measurement_window_size:]
    print("values in window:", values_in_window)

    avg_val = np.mean(values_in_window)
    excursion_up = avg_val * (1 + EXCURSION_THRESHOLD)
    excursion_down = avg_val * (1 - EXCURSION_THRESHOLD)

    if max(values_in_window) > excursion_up:
        exit(1)
    if min(values_in_window) < excursion_down:
        exit(1)

    # get rounds for the corresponding values in window; round starts from 1.
    rounds = range(len(values) - measurement_window_size + 1, len(values) + 1)

    coefficients = np.polyfit(rounds, values_in_window, 1)
    poly = np.poly1d(coefficients)
    poly_vals = poly([rounds[0], rounds[measurement_window_size - 1]])

    if max(poly_vals) > excursion_up:
        exit(1)
    if min(poly_vals) < excursion_down:
        exit(1)

    exit(0)


if __name__ == "__main__":
    main()
