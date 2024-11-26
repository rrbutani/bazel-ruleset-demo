#pragma once

#include "examples/with_deps/a.h"
#include "examples/with_deps/c.h"
// #include "c.h" // shouldn't work but does

void with_deps(A a);
