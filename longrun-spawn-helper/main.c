// longrun-spawn-helper — acquires a controlling terminal, then execs the real
// command. The parent spawns this via posix_spawn with POSIX_SPAWN_SETSID and
// the slave PTY duped onto stdin/stdout/stderr.
//
// Why a helper at all: on macOS, posix_spawn + SETSID does NOT give the child a
// controlling terminal (verified). Without one, isatty() is true but SIGWINCH
// on resize and /dev/tty don't work. The fix: as the new session leader, open
// our slave tty — "the first terminal open by a session leader (without
// O_NOCTTY) becomes the controlling terminal" (xnu). Doing this from a tiny
// helper guarantees it runs AFTER SETSID has taken effect.
//
// argv: [self, cwd, exe, args...]
//   argv[1] = working directory ("" = don't chdir)
//   argv[2] = executable to exec (absolute, already resolved by the parent)
//   argv[2..] = the real argv (exe as argv[0])

#include <unistd.h>
#include <fcntl.h>
#include <string.h>

// Write a diagnostic to stderr (the slave PTY) so a launch failure shows up in
// the terminal pane instead of a blank screen. Uses write(2) directly because
// _exit() does not flush stdio buffers.
static void diag(const char *prefix, const char *detail) {
    write(2, "longrun: ", 9);
    write(2, prefix, strlen(prefix));
    write(2, detail, strlen(detail));
    write(2, "\n", 1);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        _exit(127);
    }

    const char *tty = ttyname(STDIN_FILENO);
    if (tty) {
        int fd = open(tty, O_RDWR);  // first tty open by the session leader → controlling terminal
        if (fd >= 0) {
            close(fd);
        }
    }

    const char *cwd = argv[1];
    if (cwd[0] != '\0' && chdir(cwd) != 0) {
        diag("cannot enter working directory: ", cwd);
        _exit(127);
    }

    execvp(argv[2], &argv[2]);
    diag("failed to exec: ", argv[2]);  // exec failed (e.g. command not found)
    _exit(127);
}
