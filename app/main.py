from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import uvicorn
import os
from datetime import datetime, timezone

app = FastAPI(
    title="Python ECS Fargate API",
    description="A sample FastAPI application deployed on AWS ECS Fargate",
    version="1.0.0"
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Models
class HealthResponse(BaseModel):
    status: str
    timestamp: str
    environment: str
    branch: Optional[str] = None

class Item(BaseModel):
    id: Optional[int] = None
    name: str
    description: Optional[str] = None
    price: float

# In-memory storage (replace with database in production)
items_db = {}
item_counter = 0

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "Welcome to Python ECS Fargate API",
        "docs": "/docs",
        "health": "/health"
    }

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint for ALB/ECS"""
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "environment": os.getenv("ENVIRONMENT", "development"),
        "branch": os.getenv("BRANCH_NAME", "unknown")
    }

@app.get("/items")
async def list_items():
    """List all items"""
    return {"items": list(items_db.values()), "count": len(items_db)}

@app.post("/items", status_code=201)
async def create_item(item: Item):
    """Create a new item"""
    global item_counter
    item_counter += 1
    item.id = item_counter
    items_db[item.id] = item.dict()
    return {"message": "Item created successfully", "item": items_db[item.id]}

@app.get("/items/{item_id}")
async def get_item(item_id: int):
    """Get a specific item by ID"""
    if item_id not in items_db:
        raise HTTPException(status_code=404, detail="Item not found")
    return items_db[item_id]

@app.put("/items/{item_id}")
async def update_item(item_id: int, item: Item):
    """Update an existing item"""
    if item_id not in items_db:
        raise HTTPException(status_code=404, detail="Item not found")
    item.id = item_id
    items_db[item_id] = item.dict()
    return {"message": "Item updated successfully", "item": items_db[item_id]}

@app.delete("/items/{item_id}")
async def delete_item(item_id: int):
    """Delete an item"""
    if item_id not in items_db:
        raise HTTPException(status_code=404, detail="Item not found")
    del items_db[item_id]
    return {"message": "Item deleted successfully"}

if __name__ == "__main__":
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
