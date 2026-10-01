// The program every case builds: a C++23 program that includes <vector> and
// uses std::format, so that the toolchain under test compiles, links and runs
// against its own C++ library.
#include <format>
#include <iostream>
#include <string>
#include <vector>

int main() {
    const std::vector<int> v{1, 2, 3};
    int sum = 0;
    for (const int x : v) sum += x;
    const std::string greeting = "hello";
    std::cout << std::format("toolchain-lab: sum={} count={} greeting={} {}\n",
                             sum, v.size(), greeting, 42);
    return 0;
}
