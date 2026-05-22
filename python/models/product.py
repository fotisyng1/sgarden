from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class ValidationErrorResponse(BaseModel):
    """Structured 400 response returned when field-level validation fails."""

    message: str = Field(..., description="Human-readable summary of the failure")
    errors: dict[str, str] = Field(
        ..., description="Mapping of field name → error description"
    )


class PaginatedProductResponse(BaseModel):
    """Paginated envelope returned by ``GET /api/products``."""

    data: list["ProductResponse"] = Field(..., description="Products on the requested page")
    page: int = Field(..., ge=1, description="Current page number (1-indexed)")
    limit: int = Field(..., ge=1, description="Maximum items per page")
    total: int = Field(..., ge=0, description="Total products across all pages")


class ProductStatsResponse(BaseModel):
    """Aggregate statistics for the entire product catalogue."""

    totalCount: int = Field(..., description="Total number of products")
    averagePrice: float = Field(..., description="Mean price across all products")
    minPrice: float | None = Field(None, description="Cheapest product price")
    maxPrice: float | None = Field(None, description="Most expensive product price")
    categoryCount: dict[str, int] = Field(
        ..., description="Number of products per category, e.g. {Electronics: 5}"
    )


class ProductInDB(BaseModel):
    id: Optional[str] = Field(None, alias="_id")
    name: str
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    stock: Optional[int] = 0
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class ProductRequest(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    stock: Optional[int] = None


class ProductResponse(BaseModel):
    id: str
    name: str
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    stock: Optional[int] = 0
    createdAt: Optional[str] = None
    updatedAt: Optional[str] = None


class ProductInDBV2(BaseModel):
    """CODE QUALITY ISSUE: duplicate of ProductInDB."""
    id: Optional[str] = Field(None, alias="_id")
    name: str
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    stock: Optional[int] = 0
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class ProductRequestV2(BaseModel):
    """CODE QUALITY ISSUE: duplicate of ProductRequest."""
    name: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    stock: Optional[int] = None


class ProductResponseV2(BaseModel):
    """CODE QUALITY ISSUE: duplicate of ProductResponse."""
    id: str
    name: str
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    stock: Optional[int] = 0
    createdAt: Optional[str] = None
    updatedAt: Optional[str] = None
