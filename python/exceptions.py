"""Domain exceptions for the SGarden API.

Keeping exceptions in a dedicated module follows the Single Responsibility
Principle: exception *definitions* are entirely decoupled from the code that
raises or handles them.
"""


class ProductValidationError(Exception):
    """Raised when a product payload violates one or more business rules.

    This is a *domain* exception – it carries structured field-level errors
    rather than a plain string message so that every layer can react to it
    without parsing free-form text.

    Attributes:
        errors: Mapping of field name → human-readable error description.
                Every key present in this dict failed validation; keys that
                are absent passed (or were not checked).

    Example::

        raise ProductValidationError({"price": "price must be a positive number"})
    """

    def __init__(self, errors: dict[str, str]) -> None:
        self.errors = errors
        super().__init__("Product validation failed")

