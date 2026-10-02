#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
// Hold until exit, never unlink: unlink would allow two independent lock inodes.
static int CLSimulatorProcessLease(NSString *label) {
    NSString *path = [NSString stringWithFormat:@"/private/tmp/cl-local-simulator-%u-%@.lock", getuid(), label];
    int fd = open(path.fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
    struct stat st;
    if (fd < 0) return -1;
    if (fstat(fd, &st) || st.st_uid != getuid() || !S_ISREG(st.st_mode) || flock(fd, LOCK_EX | LOCK_NB)) {
        close(fd); return -1;
    }
    return fd;
}
