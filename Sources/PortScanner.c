#include "PortScanner.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static struct proc_fdinfo *file_descriptors(int pid, int *count) {
    int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (bytes <= 0) return NULL;
    // Allow descriptors to be opened between the two kernel calls.
    bytes += 64 * (int)sizeof(struct proc_fdinfo);
    struct proc_fdinfo *fds = malloc((size_t)bytes);
    if (!fds) return NULL;
    int used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, bytes);
    if (used <= 0) { free(fds); return NULL; }
    *count = used / (int)sizeof(*fds);
    return fds;
}

static int listener(int pid, int fd, struct socket_fdinfo *socket) {
    return proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, socket, sizeof(*socket)) == sizeof(*socket)
        && socket->psi.soi_kind == SOCKINFO_TCP
        && socket->psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN;
}

PortRecord *ports_scan(int32_t *count) {
    *count = 0;
    int capacity = proc_listallpids(NULL, 0) + 256;
    if (capacity < 256) { *count = -1; return NULL; }
    int *pids = calloc((size_t)capacity, sizeof(int));
    if (!pids) { *count = -1; return NULL; }
    int n = proc_listallpids(pids, capacity * (int)sizeof(int));
    if (n < 0) { free(pids); *count = -1; return NULL; }
    int slots = 32;
    PortRecord *records = calloc((size_t)slots, sizeof(*records));
    if (!records) { free(pids); *count = -1; return NULL; }
    for (int p = 0; p < n; p++) {
        int pid = pids[p];
        if (pid <= 0 || pid == getpid()) continue;
        struct proc_bsdinfo info;
        if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) continue;
        int fd_count = 0;
        struct proc_fdinfo *fds = file_descriptors(pid, &fd_count);
        if (!fds) continue;
        PortRecord base = {0};
        base.pid = pid;
        base.uid = info.pbi_uid;
        base.start_sec = info.pbi_start_tvsec;
        base.start_usec = info.pbi_start_tvusec;
        int has_metadata = 0;
        for (int f = 0; f < fd_count; f++) {
            if (fds[f].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
            struct socket_fdinfo socket;
            if (!listener(pid, fds[f].proc_fd, &socket)) continue;
            if (!has_metadata) {
                proc_pidpath(pid, base.executable, sizeof(base.executable));
                strlcpy(base.name, info.pbi_name[0] ? info.pbi_name : info.pbi_comm, sizeof(base.name));
                struct proc_vnodepathinfo cwd;
                if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &cwd, sizeof(cwd)) == sizeof(cwd))
                    strlcpy(base.directory, cwd.pvi_cdir.vip_path, sizeof(base.directory));
                has_metadata = 1;
            }
            const struct in_sockinfo *in = &socket.psi.soi_proto.pri_tcp.tcpsi_ini;
            PortRecord record = base;
            record.port = ntohs((uint16_t)in->insi_lport);
            record.family = socket.psi.soi_family;
            if (record.family == AF_INET)
                inet_ntop(AF_INET, &in->insi_laddr.ina_46.i46a_addr4, record.address, sizeof(record.address));
            else if (record.family == AF_INET6)
                inet_ntop(AF_INET6, &in->insi_laddr.ina_6, record.address, sizeof(record.address));
            else continue;
            if (!record.port) continue;
            if (*count == slots) {
                slots *= 2;
                PortRecord *grown = realloc(records, (size_t)slots * sizeof(*records));
                if (!grown) { free(records); free(fds); free(pids); *count = -1; return NULL; }
                records = grown;
            }
            records[(*count)++] = record;
        }
        free(fds);
    }
    free(pids);
    return records;
}

void ports_free(PortRecord *records) { free(records); }

int ports_stop(int32_t pid, uint64_t sec, uint64_t usec, uint16_t port, int force) {
    if (pid <= 1 || pid == getpid()) return EPERM;
    struct proc_bsdinfo info;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) return ESRCH;
    if (info.pbi_uid != getuid()) return EPERM;
    if (info.pbi_start_tvsec != sec || info.pbi_start_tvusec != usec) return ESTALE;
    char path[4096] = {0};
    proc_pidpath(pid, path, sizeof(path));
    if (!strncmp(path, "/System/", 8) || !strncmp(path, "/usr/libexec/", 13)
        || !strncmp(path, "/usr/sbin/", 10)) return EPERM;
    int count = 0, found = 0;
    struct proc_fdinfo *fds = file_descriptors(pid, &count);
    if (!fds) return ESRCH;
    for (int f = 0; f < count && !found; f++) {
        struct socket_fdinfo socket;
        if (fds[f].proc_fdtype == PROX_FDTYPE_SOCKET && listener(pid, fds[f].proc_fd, &socket))
            found = ntohs((uint16_t)socket.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport) == port;
    }
    free(fds);
    if (!found) return ESRCH;
    // Recheck after enumeration; never signal a recycled PID from an old UI row.
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) return ESRCH;
    if (info.pbi_start_tvsec != sec || info.pbi_start_tvusec != usec) return ESTALE;
    if (info.pbi_uid != getuid()) return EPERM;
    return kill(pid, force ? SIGKILL : SIGTERM) == 0 ? 0 : errno;
}
