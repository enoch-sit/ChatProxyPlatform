"""Lightweight exception types that can be imported without heavy dependencies."""


class FlowiseAPIError(Exception):
    """Raised when the Flowise API returns a non-200 response or is unreachable."""

    def __init__(self, message: str, status_code: int | None = None):
        self.status_code = status_code
        super().__init__(message)
