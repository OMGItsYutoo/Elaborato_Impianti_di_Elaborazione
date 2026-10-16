#!/bin/bash

# Array di coppie "NomeFile:DimensioneInByte"
# Nota: La dimensione raw per head -c tiene conto dell'encoding base64 (4/3 del valore raw)
# per fare in modo che il file HTML finale rispetti circa il target desiderato.

declare -A PAGES=(
  ["page_150k.html"]="110K"
  ["page_350k.html"]="255K"
  ["page_850k.html"]="620K"
  ["page_1m5.html"]="1100K"
  ["page_3m.html"]="2200K"
  ["page_7m.html"]="5200K"
  ["page_9m5.html"]="7000K"
  ["page_12m.html"]="8900K"
  ["page_15m.html"]="11100K"
)

# 1. Pagina da ~150 KB
cat << 'EOF' > page_150k.html
<!DOCTYPE html>
<html lang="it">
<head><meta charset="UTF-8"><title>Test 150KB</title></head>
<body>
<h1>Pagina di Test - 150 KB</h1>
<!-- PADDING_START
EOF
head -c 110K /dev/urandom | base64 | tr -d '\n' >> page_150k.html
cat << 'EOF' >> page_150k.html
PADDING_END -->
</body>
</html>
EOF

# 2. Pagina da ~350 KB
cat << 'EOF' > page_350k.html
<!DOCTYPE html>
<html lang="it">
<head><meta charset="UTF-8"><title>Test 350KB</title></head>
<body>
<h1>Pagina di Test - 350 KB</h1>
<!-- PADDING_START
EOF
head -c 255K /dev/urandom | base64 | tr -d '\n' >> page_350k.html
cat << 'EOF' >> page_350k.html
PADDING_END -->
</body>
</html>
EOF

# 3. Pagina da ~850 KB
cat << 'EOF' > page_850k.html
<!DOCTYPE html>
<html lang="it">
<head><meta charset="UTF-8"><title>Test 850KB</title></head>
<body>
<h1>Pagina di Test - 850 KB</h1>
<!-- PADDING_START
EOF
head -c 620K /dev/urandom | base64 | tr -d '\n' >> page_850k.html
cat << 'EOF' >> page_850k.html
PADDING_END -->
</body>
</html>
EOF

# 4. Pagina da ~1.5 MB
cat << 'EOF' > page_1m5.html
<!DOCTYPE html>
<html lang="it">
<head><meta charset="UTF-8"><title>Test 1.5MB</title></head>
<body>
<h1>Pagina di Test - 1.5 MB</h1>
<!-- PADDING_START
EOF
head -c 1100K /dev/urandom | base64 | tr -d '\n' >> page_1m5.html
cat << 'EOF' >> page_1m5.html
PADDING_END -->
</body>
</html>
EOF

# 5. Pagina da ~3 MB
cat << 'EOF' > page_3m.html
<!DOCTYPE html>
<html lang="it">
<head><meta charset="UTF-8"><title>Test 3MB</title></head>
<body>
<h1>Pagina di Test - 3 MB</h1>
<!-- PADDING_START
EOF
head -c 2200K /dev/urandom | base64 | tr -d '\n' >> page_3m.html
cat << 'EOF' >> page_3m.html
PADDING_END -->
</body>
</html>
EOF

# 6. Pagina da ~7 MB
cat << 'EOF' > page_7m.html
<!DOCTYPE html>
<html lang="it">
<head><meta charset="UTF-8"><title>Test 7MB</title></head>
<body>
<h1>Pagina di Test - 7 MB</h1>
<!-- PADDING_START
EOF
head -c 5200K /dev/urandom | base64 | tr -d '\n' >> page_7m.html
cat << 'EOF' >> page_7m.html
PADDING_END -->
</body>
</html>
EOF

# 7. Pagina da ~9.5 MB
cat << 'EOF' > page_9m5.html
<!DOCTYPE html>
<html lang="it">
<head><meta charset="UTF-8"><title>Test 9.5MB</title></head>
<body>
<h1>Pagina di Test - 9.5 MB</h1>
<!-- PADDING_START
EOF
head -c 7000K /dev/urandom | base64 | tr -d '\n' >> page_9m5.html
cat << 'EOF' >> page_9m5.html
PADDING_END -->
</body>
</html>
EOF

# 8. Pagina da ~12 MB
cat << 'EOF' > page_12m.html
<!DOCTYPE html>
<html lang="it">
<head><meta charset="UTF-8"><title>Test 12MB</title></head>
<body>
<h1>Pagina di Test - 12 MB</h1>
<!-- PADDING_START
EOF
head -c 8900K /dev/urandom | base64 | tr -d '\n' >> page_12m.html
cat << 'EOF' >> page_12m.html
PADDING_END -->
</body>
</html>
EOF

# 9. Pagina da ~15 MB
cat << 'EOF' > page_15m.html
<!DOCTYPE html>
<html lang="it">
<head><meta charset="UTF-8"><title>Test 15MB</title></head>
<body>
<h1>Pagina di Test - 15 MB</h1>
<!-- PADDING_START
EOF
head -c 11100K /dev/urandom | base64 | tr -d '\n' >> page_15m.html
cat << 'EOF' >> page_15m.html
PADDING_END -->
</body>
</html>
EOF
