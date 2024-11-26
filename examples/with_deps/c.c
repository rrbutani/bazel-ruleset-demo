#include "with_deps/c.h"
#include "examples/with_deps/cpuid_example.h"
#include <stdio.h>

void c(A a_, B b_) {
    printf("in C; calling a and b\n");
    a(a_); b(b_);

    printf("\nprocessor info:\n");
    (void)cpuinfo();
}
