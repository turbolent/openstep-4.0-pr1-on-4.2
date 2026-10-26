"""Shared file modes and checked-input validation for the app builders."""

EXECUTABLE_MODE = 0o755
FILE_MODE = 0o644
SYMLINK_MODE = 0o777
TAR_NAME_SIZE = 100


def require(condition, message):
    if not condition:
        raise ValueError(message)
