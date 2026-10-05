#ifndef PORT_SCANNER_H
#define PORT_SCANNER_H
#include <stdint.h>

typedef struct {
    int32_t pid;
    uint32_t uid;
    uint64_t start_sec, start_usec;
    uint16_t port;
    int32_t family;
    char address[64];
    char name[256];
    char executable[4096];
    char directory[1024];
} PortRecord;

// Caller owns the returned array. No subprocesses, traffic or elevated access.
PortRecord *ports_scan(int32_t *count);
void ports_free(PortRecord *records);
// Revalidate identity, ownership and listening port immediately before signaling.
int ports_stop(int32_t pid, uint64_t sec, uint64_t usec, uint16_t port, int force);
#endif
