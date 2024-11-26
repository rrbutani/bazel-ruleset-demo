#include "with_deps.h"

void with_deps(A a) {
    B b = { a.a * 2 };
    c(a, b);
}

int main(int argc, char** argv, char** environ) {
    with_deps((A){ argc });
}
