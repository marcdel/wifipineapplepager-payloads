#!/bin/sh

RECON_DB="/root/recon/recon.db"
AUTH_CHALLENGE_FILE="/tmp/recon_db_explorer_auth_challenge"
AUTH_SESSION_FILE="/tmp/recon_db_explorer_auth_session"
SESSION_TIMEOUT=3600

# Authentication functions (adapted from nautilus)
generate_challenge() {
    local challenge=$(head -c 32 /dev/urandom 2>/dev/null | md5sum | cut -d' ' -f1)
    local timestamp=$(date +%s)
    echo "${challenge}:${timestamp}" > "$AUTH_CHALLENGE_FILE"
    echo "Content-Type: application/json"
    echo ""
    echo "{\"challenge\":\"$challenge\"}"
}

verify_auth() {
    local nonce="$1"
    local encrypted_b64="$2"

    if [ ! -f "$AUTH_CHALLENGE_FILE" ]; then
        echo "Content-Type: application/json"
        echo ""
        echo '{"error":"No challenge issued"}'
        exit 1
    fi

    local stored=$(cat "$AUTH_CHALLENGE_FILE")
    local stored_challenge="${stored%%:*}"
    local stored_time="${stored##*:}"
    local now=$(date +%s)

    if [ $((now - stored_time)) -gt 60 ]; then
        rm -f "$AUTH_CHALLENGE_FILE"
        echo "Content-Type: application/json"
        echo ""
        echo '{"error":"Challenge expired"}'
        exit 1
    fi

    if [ "$nonce" != "$stored_challenge" ]; then
        echo "Content-Type: application/json"
        echo ""
        echo '{"error":"Invalid challenge"}'
        exit 1
    fi

    rm -f "$AUTH_CHALLENGE_FILE"

    local key_hex=$(printf '%s' "$nonce" | openssl dgst -sha256 -hex 2>/dev/null | cut -d' ' -f2)
    local encrypted_hex=$(echo "$encrypted_b64" | base64 -d 2>/dev/null | hexdump -ve '1/1 "%02x"' 2>/dev/null)

    if [ -z "$encrypted_hex" ]; then
        echo "Content-Type: application/json"
        echo ""
        echo '{"error":"Decode failed"}'
        exit 1
    fi

    if [ ${#encrypted_hex} -gt 256 ]; then
        echo "Content-Type: application/json"
        echo ""
        echo '{"error":"Password too long"}'
        exit 1
    fi

    local password=""
    local i=0
    local len=${#encrypted_hex}
    local key_len=${#key_hex}
    while [ $i -lt $len ]; do
        local enc_byte=$(expr substr "$encrypted_hex" $((i + 1)) 2)
        local key_pos=$(( (i % key_len) + 1 ))
        local key_byte=$(expr substr "$key_hex" $key_pos 2)
        local dec_byte=$(printf '%02x' $((0x$enc_byte ^ 0x$key_byte)))
        password="${password}$(printf "\\x${dec_byte}")"
        i=$((i + 2))
    done

    local shadow_entry=$(grep '^root:' /etc/shadow 2>/dev/null)
    local shadow_hash=$(echo "$shadow_entry" | cut -d: -f2)
    local salt=$(echo "$shadow_hash" | cut -d'$' -f1-3)

    local test_hash=$(openssl passwd -1 -salt "$(echo "$salt" | cut -d'$' -f3)" "$password" 2>/dev/null)

    if [ "$test_hash" = "$shadow_hash" ]; then
        local session=$(head -c 32 /dev/urandom 2>/dev/null | md5sum | cut -d' ' -f1)
        local session_time=$(date +%s)
        echo "${session}:${session_time}" > "$AUTH_SESSION_FILE"
        echo "Content-Type: application/json"
        echo "Set-Cookie: recon_session=$session; Path=/; HttpOnly; SameSite=Strict"
        echo ""
        echo '{"success":true}'
    else
        echo "Content-Type: application/json"
        echo ""
        echo '{"error":"Invalid password"}'
    fi
}

check_session() {
    local session=""
    local cookies="$HTTP_COOKIE"
    local IFS=';'
    for cookie in $cookies; do
        cookie=$(echo "$cookie" | sed 's/^ *//')
        case "$cookie" in
            recon_session=*)
                session="${cookie#recon_session=}"
                ;;
        esac
    done
    unset IFS

    if [ -z "$session" ]; then
        return 1
    fi

    if [ ! -f "$AUTH_SESSION_FILE" ]; then
        return 1
    fi

    local stored=$(cat "$AUTH_SESSION_FILE")
    local stored_session="${stored%%:*}"
    local stored_time="${stored##*:}"
    local now=$(date +%s)

    if [ $((now - stored_time)) -gt $SESSION_TIMEOUT ]; then
        rm -f "$AUTH_SESSION_FILE"
        return 1
    fi

    if [ "$session" = "$stored_session" ]; then
        return 0
    fi

    return 1
}

require_auth() {
    if ! check_session; then
        echo "Content-Type: application/json"
        echo ""
        echo '{"error":"Authentication required","code":"AUTH_REQUIRED"}'
        exit 1
    fi
}

urldecode() {
    printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

# Database functions
list_tables() {
    echo "Content-Type: application/json"
    echo ""
    
    if [ ! -f "$RECON_DB" ]; then
        echo '{"error":"Database not found","path":"'"$RECON_DB"'"}'
        exit 0
    fi
    
    local tables=$(sqlite3 "$RECON_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")
    local json="["
    local first=1
    for table in $tables; do
        [ "$first" = "0" ] && json="$json,"
        first=0
        local count=$(sqlite3 "$RECON_DB" "SELECT COUNT(*) FROM \"$table\";")
        json="$json{\"name\":\"$table\",\"count\":$count}"
    done
    json="$json]"
    echo "{\"tables\":$json}"
}

get_table_count() {
    local table="$1"
    echo "Content-Type: application/json"
    echo ""
    
    if [ ! -f "$RECON_DB" ]; then
        echo '{"error":"Database not found"}'
        exit 0
    fi
    
    # Validate table name (alphanumeric and underscore only)
    case "$table" in
        *[!a-zA-Z0-9_]*) 
            echo '{"error":"Invalid table name"}'
            exit 0
            ;;
    esac
    
    local count=$(sqlite3 "$RECON_DB" "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null)
    if [ -z "$count" ]; then
        echo '{"error":"Table not found"}'
        exit 0
    fi
    echo "{\"table\":\"$table\",\"count\":$count}"
}

query_table() {
    local table="$1"
    local limit="$2"
    local offset="$3"
    
    echo "Content-Type: application/json"
    echo ""
    
    if [ ! -f "$RECON_DB" ]; then
        echo '{"error":"Database not found"}'
        exit 0
    fi
    
    # Validate table name
    case "$table" in
        *[!a-zA-Z0-9_]*) 
            echo '{"error":"Invalid table name"}'
            exit 0
            ;;
    esac
    
    # Default and sanitize limit/offset
    [ -z "$limit" ] && limit=50
    [ -z "$offset" ] && offset=0
    limit=$(echo "$limit" | grep -o '^[0-9]*' | head -1)
    offset=$(echo "$offset" | grep -o '^[0-9]*' | head -1)
    [ -z "$limit" ] && limit=50
    [ -z "$offset" ] && offset=0
    [ "$limit" -gt 500 ] && limit=500
    
    # Get column names
    local columns=$(sqlite3 "$RECON_DB" "PRAGMA table_info(\"$table\");" 2>/dev/null | cut -d'|' -f2)
    if [ -z "$columns" ]; then
        echo '{"error":"Table not found"}'
        exit 0
    fi
    
    # Build columns JSON array
    local cols_json="["
    local first=1
    for col in $columns; do
        [ "$first" = "0" ] && cols_json="$cols_json,"
        first=0
        cols_json="$cols_json\"$col\""
    done
    cols_json="$cols_json]"
    
    # Get total count
    local total=$(sqlite3 "$RECON_DB" "SELECT COUNT(*) FROM \"$table\";")
    
    # Query data as JSON
    local data=$(sqlite3 -json "$RECON_DB" "SELECT * FROM \"$table\" LIMIT $limit OFFSET $offset;" 2>/dev/null)
    
    # If -json not supported, fall back to manual JSON construction
    if [ -z "$data" ] || echo "$data" | grep -q "Error"; then
        data="[]"
        local rows=$(sqlite3 -separator '|' "$RECON_DB" "SELECT * FROM \"$table\" LIMIT $limit OFFSET $offset;" 2>/dev/null)
        if [ -n "$rows" ]; then
            data="["
            local row_first=1
            echo "$rows" | while IFS= read -r row; do
                [ "$row_first" = "0" ] && printf ","
                row_first=0
                printf "{"
                local col_idx=0
                local col_first=1
                for col in $columns; do
                    [ "$col_first" = "0" ] && printf ","
                    col_first=0
                    col_idx=$((col_idx + 1))
                    local val=$(echo "$row" | cut -d'|' -f$col_idx)
                    # Escape JSON special chars
                    val=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')
                    printf '"%s":"%s"' "$col" "$val"
                done
                printf "}"
            done
            data="$data]"
        fi
    fi
    
    echo "{\"table\":\"$table\",\"columns\":$cols_json,\"total\":$total,\"limit\":$limit,\"offset\":$offset,\"data\":$data}"
}

get_schema() {
    local table="$1"
    echo "Content-Type: application/json"
    echo ""
    
    if [ ! -f "$RECON_DB" ]; then
        echo '{"error":"Database not found"}'
        exit 0
    fi
    
    # Validate table name
    case "$table" in
        *[!a-zA-Z0-9_]*) 
            echo '{"error":"Invalid table name"}'
            exit 0
            ;;
    esac
    
    local schema=$(sqlite3 "$RECON_DB" "PRAGMA table_info(\"$table\");" 2>/dev/null)
    if [ -z "$schema" ]; then
        echo '{"error":"Table not found"}'
        exit 0
    fi
    
    local json="["
    local first=1
    echo "$schema" | while IFS='|' read -r cid name type notnull dflt pk; do
        [ "$first" = "0" ] && printf ","
        first=0
        printf '{"cid":%s,"name":"%s","type":"%s","notnull":%s,"default":%s,"pk":%s}' \
            "$cid" "$name" "$type" "$notnull" "${dflt:-null}" "$pk"
    done
    echo "$json]"
}

# Parse query string
action=""
nonce=""
data=""
table=""
limit=""
offset=""

IFS='&'
for param in $QUERY_STRING; do
    key="${param%%=*}"
    val="${param#*=}"
    case "$key" in
        action) action="$val" ;;
        nonce) nonce=$(urldecode "$val") ;;
        data) data=$(urldecode "$val") ;;
        table) table=$(urldecode "$val") ;;
        limit) limit=$(urldecode "$val") ;;
        offset) offset=$(urldecode "$val") ;;
    esac
done
unset IFS

# Route requests
case "$action" in
    challenge)
        generate_challenge
        ;;
    auth)
        verify_auth "$nonce" "$data"
        ;;
    check_session)
        if check_session; then
            echo "Content-Type: application/json"
            echo ""
            echo '{"authenticated":true}'
        else
            echo "Content-Type: application/json"
            echo ""
            echo '{"authenticated":false}'
        fi
        ;;
    tables)
        require_auth
        list_tables
        ;;
    count)
        require_auth
        get_table_count "$table"
        ;;
    query)
        require_auth
        query_table "$table" "$limit" "$offset"
        ;;
    schema)
        require_auth
        get_schema "$table"
        ;;
    *)
        echo "Content-Type: application/json"
        echo ""
        echo '{"error":"Unknown action"}'
        ;;
esac
