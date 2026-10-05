#include "../Sources/PortScanner.h"
#include <stdio.h>
#include <time.h>
int main(void) {
    const int iterations = 100;
    clock_t start = clock();
    int32_t count = 0;
    for (int i = 0; i < iterations; i++) {
        PortRecord *records = ports_scan(&count);
        if (count < 0) return 1;
        ports_free(records);
    }
    double ms = 1000.0 * (clock() - start) / CLOCKS_PER_SEC / iterations;
    printf("%d sockets; %.2f ms CPU/scan; about %.2f%% of one CPU at a 2s interval\n", count, ms, ms / 20.0);
}
