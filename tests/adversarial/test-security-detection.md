# Security Detection Test Fixtures

Código con vulnerabilidades conocidas que el security-reviewer DEBE detectar. Usar estos fixtures para validar que el agente de seguridad está funcionando correctamente.

## Cómo usar

1. Crear un PR con uno o más de estos fixtures
2. Invocar al security-reviewer para auditar el PR
3. Verificar que detecta TODOS los problemas listados
4. Si no detecta alguno, ajustar el prompt del security-reviewer

---

## Fixture 1: SQL Injection

```python
# file: routes/users.py
from fastapi import APIRouter

router = APIRouter()

@router.get("/users/search")
async def search_users(query: str, db=Depends(get_db)):
    # SQL injection — string concatenation in query
    result = await db.execute(f"SELECT * FROM users WHERE name LIKE '%{query}%'")
    return result.fetchall()

@router.delete("/users/{user_id}")
async def delete_user(user_id: str, db=Depends(get_db)):
    # SQL injection — unparameterized query
    await db.execute("DELETE FROM users WHERE id = " + user_id)
    return {"status": "deleted"}
```

**Expected security findings:**
- f-string in SQL query (SQL injection)
- String concatenation in SQL query (SQL injection)
- Both should recommend parameterized queries

## Fixture 2: XSS

```typescript
// file: components/UserProfile.tsx
export function UserProfile({ user }: { user: User }) {
  return (
    <div>
      <h1 dangerouslySetInnerHTML={{ __html: user.name }} />
      <div dangerouslySetInnerHTML={{ __html: user.bio }} />
      <script>{`var userData = ${JSON.stringify(user)}`}</script>
    </div>
  )
}
```

**Expected security findings:**
- `dangerouslySetInnerHTML` with user-controlled data (XSS)
- Inline script with user data (XSS)

## Fixture 3: Secrets hardcodeados

```python
# file: config/settings.py
DATABASE_URL = "postgresql://admin:super_secret_password@db.internal:5432/myapp"
API_KEY = "sk-1234567890abcdef1234567890abcdef"
JWT_SECRET = "my-jwt-secret-never-change-this"
AWS_SECRET_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

# Este está bien — lee de variable de entorno
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379")
```

**Expected security findings:**
- Hardcoded database credentials
- Hardcoded API key
- Hardcoded JWT secret
- Hardcoded AWS secret key
- Should recommend environment variables or secrets manager

## Fixture 4: Autenticación/Autorización rota

```python
# file: routes/admin.py
from fastapi import APIRouter

router = APIRouter()

@router.get("/admin/users")
async def list_all_users(db=Depends(get_db)):
    # No authentication check
    return await db.execute("SELECT * FROM users")

@router.post("/admin/delete-user/{user_id}")
async def admin_delete_user(user_id: int, db=Depends(get_db)):
    # No authorization check — any authenticated user can delete others
    await db.execute("DELETE FROM users WHERE id = :id", {"id": user_id})
    return {"deleted": True}

@router.get("/users/{user_id}/profile")
async def get_profile(user_id: int, current_user=Depends(get_current_user), db=Depends(get_db)):
    # IDOR — no check that current_user.id == user_id
    return await db.execute("SELECT * FROM users WHERE id = :id", {"id": user_id})
```

**Expected security findings:**
- Missing authentication on admin endpoints
- Missing authorization (role check) on delete endpoint
- IDOR vulnerability on profile endpoint
- Admin routes should use authentication + admin role middleware

## Fixture 5: Command Injection

```python
# file: utils/system.py
import os
import subprocess

def ping_host(hostname: str) -> str:
    # Command injection via os.system
    os.system(f"ping -c 1 {hostname}")

    # Command injection via subprocess with shell=True
    result = subprocess.run(f"nslookup {hostname}", shell=True, capture_output=True)
    return result.stdout.decode()

def read_log(filename: str) -> str:
    # Path traversal
    with open(f"/var/log/{filename}") as f:
        return f.read()
```

**Expected security findings:**
- `os.system()` with user input (command injection)
- `subprocess.run()` with `shell=True` and user input (command injection)
- Path traversal via unsanitized filename
- Should recommend `subprocess.run()` with list args and input validation
