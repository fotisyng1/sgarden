"""Domain exceptions for the SGarden API."""


class DomainValidationError(Exception):
    """Base class for all domain-level validation failures.

    Carries a structured ``errors`` mapping so every layer can react to
    field-level problems without parsing free-form text.

    Attributes:
        errors: Mapping of field name → human-readable error description.
    """

    def __init__(self, errors: dict[str, str]) -> None:
        self.errors = errors
        super().__init__("Validation failed")


class ProductValidationError(DomainValidationError):
    """Raised when a product payload violates one or more business rules."""


class OrderValidationError(DomainValidationError):
    """Raised when an order payload violates one or more business rules."""
