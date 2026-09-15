import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/** Synthetic, loopback-only S3 protocol fixture; never accepts real credentials. */
class R2ContractServer {
    private static final String ACCESS = "contract-access";
    private static final String SECRET = "contract-secret";
    private static final Map<String, StoredObject> OBJECTS = new ConcurrentHashMap<>();
    private static final List<Event> EVENTS = java.util.Collections.synchronizedList(new ArrayList<>());

    record StoredObject(byte[] body, String contentType) {}
    record Event(String method, String path, boolean valid, String error) {}

    public static void main(String[] args) throws Exception {
        var server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", R2ContractServer::handle);
        server.setExecutor(Executors.newCachedThreadPool());
        server.start();
        System.out.println(server.getAddress().getPort());
        System.out.flush();
        // The CommandBox task or TestBox spec owns this child process.
        Thread.currentThread().join();
    }

    private static void handle(HttpExchange exchange) throws java.io.IOException {
        try {
            if (exchange.getRequestURI().getPath().equals("/__evidence")) {
                respond(exchange, 200, evidence().getBytes(StandardCharsets.UTF_8), "application/json", null);
                return;
            }
            byte[] body = exchange.getRequestBody().readAllBytes();
            var headers = new HashMap<String, String>();
            exchange.getRequestHeaders().forEach((name, values) ->
                headers.put(name.toLowerCase(java.util.Locale.ROOT), values.get(0)));
            var query = parseQuery(exchange.getRequestURI().getRawQuery());
            String method = exchange.getRequestMethod();
            String path = exchange.getRequestURI().getPath();
            try {
                require(!headers.containsKey("x-amz-acl") && !query.containsKey("acl"), "ACL unsupported");
                verifySignature(exchange, headers, query, body);
                require(path.startsWith("/private-contract/") || path.startsWith("/public-contract/"),
                    "wrong bucket or addressing style");
                EVENTS.add(new Event(method, path, true, null));
            } catch (Exception error) {
                EVENTS.add(new Event(method, path, false, error.getMessage()));
                respond(exchange, 403,
                    ("<Error><Code>AccessDenied</Code><Message>" + error.getMessage()
                        + "</Message></Error>").getBytes(StandardCharsets.UTF_8),
                    "application/xml", null);
                return;
            }

            if (method.equals("PUT") && headers.containsKey("x-amz-copy-source")) {
                if (path.endsWith("/fail-copy.pdf")) {
                    respond(exchange, 403,
                        "<Error><Code>AccessDenied</Code><Message>copy denied</Message></Error>"
                            .getBytes(StandardCharsets.UTF_8),
                        "application/xml", null);
                    return;
                }
                var source = decode(headers.get("x-amz-copy-source"));
                var object = OBJECTS.get(source);
                if (object == null) {
                    respond(exchange, 404, new byte[0], null, null);
                    return;
                }
                OBJECTS.put(path, object);
                respond(exchange, 200,
                    "<CopyObjectResult><ETag>\"copied\"</ETag></CopyObjectResult>"
                        .getBytes(StandardCharsets.UTF_8),
                    "application/xml", null);
                return;
            }
            if (method.equals("PUT")) {
                OBJECTS.put(path, new StoredObject(body,
                    headers.getOrDefault("content-type", "application/octet-stream")));
                respond(exchange, 200, new byte[0], null, "\"" + md5(body) + "\"");
                return;
            }
            if (method.equals("DELETE")) {
                OBJECTS.remove(path);
                respond(exchange, 204, new byte[0], null, null);
                return;
            }
            var object = OBJECTS.get(path);
            if (object == null) {
                respond(exchange, 404, new byte[0], null, null);
                return;
            }
            respond(exchange, 200, object.body(), object.contentType(),
                "\"" + md5(object.body()) + "\"");
        } finally {
            exchange.close();
        }
    }

    private static void verifySignature(HttpExchange exchange, Map<String, String> headers,
                                        Map<String, String> query, byte[] body) throws Exception {
        String credential, signed, supplied, stamp, payload;
        if (query.containsKey("X-Amz-Signature")) {
            credential = query.get("X-Amz-Credential");
            signed = query.get("X-Amz-SignedHeaders");
            supplied = query.remove("X-Amz-Signature");
            stamp = query.get("X-Amz-Date");
            payload = "UNSIGNED-PAYLOAD";
            int seconds = Integer.parseInt(query.get("X-Amz-Expires"));
            require(seconds >= 1 && seconds <= 900, "unbounded signed URL");
        } else {
            var auth = headers.get("authorization");
            require(auth != null && auth.startsWith("AWS4-HMAC-SHA256 "), "wrong signing algorithm");
            var fields = new HashMap<String, String>();
            for (var part : auth.substring(17).split(",")) {
                var pair = part.trim().split("=", 2);
                fields.put(pair[0], pair[1]);
            }
            credential = fields.get("Credential");
            signed = fields.get("SignedHeaders");
            supplied = fields.get("Signature");
            stamp = headers.get("x-amz-date");
            payload = headers.getOrDefault("x-amz-content-sha256", sha256(body));
            require(payload.equals(sha256(body)), "body hash mismatch");
        }
        var scopeParts = credential.split("/", -1);
        require(scopeParts.length == 5, "invalid credential scope");
        var access = scopeParts[0];
        var date = scopeParts[1];
        var region = scopeParts[2];
        var service = scopeParts[3];
        var terminator = scopeParts[4];
        require(access.equals(ACCESS) && service.equals("s3")
            && terminator.equals("aws4_request"), "invalid credential scope");
        require(region.equals("auto") || region.isEmpty() || region.equals("us-east-1"),
            "unsupported R2 signing region");
        var canonicalQuery = new ArrayList<String>();
        query.forEach((key, value) -> canonicalQuery.add(awsEncode(key) + "=" + awsEncode(value)));
        canonicalQuery.sort(Comparator.naturalOrder());
        var canonicalHeaders = new StringBuilder();
        for (var name : signed.split(";")) {
            var value = headers.get(name);
            require(value != null, "missing signed header");
            canonicalHeaders.append(name).append(":")
                .append(String.join(" ", value.trim().split("\\s+"))).append("\n");
        }
        var canonical = String.join("\n", exchange.getRequestMethod(),
            awsEncodePath(decode(exchange.getRequestURI().getRawPath())),
            String.join("&", canonicalQuery), canonicalHeaders.toString(), signed, payload);
        var scope = String.join("/", date, region, service, terminator);
        var toSign = String.join("\n", "AWS4-HMAC-SHA256", stamp, scope,
            sha256(canonical.getBytes(StandardCharsets.UTF_8)));
        byte[] signing = ("AWS4" + SECRET).getBytes(StandardCharsets.UTF_8);
        for (var part : Arrays.asList(date, region, service, terminator)) {
            signing = hmac(signing, part);
        }
        require(MessageDigest.isEqual(hex(hmac(signing, toSign)).getBytes(StandardCharsets.US_ASCII),
            supplied.getBytes(StandardCharsets.US_ASCII)), "signature mismatch");
    }

    private static Map<String, String> parseQuery(String raw) {
        var result = new HashMap<String, String>();
        if (raw != null) {
            for (var item : raw.split("&")) {
                var pair = item.split("=", 2);
                result.put(decode(pair[0]), pair.length == 2 ? decode(pair[1]) : "");
            }
        }
        return result;
    }

    private static String decode(String encoded) {
        return URLDecoder.decode(encoded.replace("+", "%2B"), StandardCharsets.UTF_8);
    }

    private static String awsEncodePath(String value) {
        return awsEncode(value).replace("%2F", "/");
    }

    private static String awsEncode(String value) {
        var output = new StringBuilder();
        for (byte octet : value.getBytes(StandardCharsets.UTF_8)) {
            int c = octet & 0xff;
            if (c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z'
                || c >= '0' && c <= '9' || c == '-' || c == '_' || c == '.' || c == '~') {
                output.append((char) c);
            } else {
                output.append('%').append(String.format("%02X", c));
            }
        }
        return output.toString();
    }

    private static byte[] hmac(byte[] key, String value) throws Exception {
        var mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key, "HmacSHA256"));
        return mac.doFinal(value.getBytes(StandardCharsets.UTF_8));
    }

    private static String sha256(byte[] bytes) throws Exception {
        return hex(MessageDigest.getInstance("SHA-256").digest(bytes));
    }

    private static String md5(byte[] bytes) {
        try {
            return hex(MessageDigest.getInstance("MD5").digest(bytes));
        } catch (Exception error) {
            throw new IllegalStateException(error);
        }
    }

    private static String hex(byte[] bytes) {
        return java.util.HexFormat.of().formatHex(bytes);
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message);
    }

    private static String evidence() {
        var result = new StringBuilder("[");
        synchronized (EVENTS) {
            for (var event : EVENTS) {
                if (result.length() > 1) result.append(",");
                result.append("{\"method\":\"").append(event.method())
                    .append("\",\"path\":\"").append(event.path())
                    .append("\",\"valid\":").append(event.valid());
                if (event.error() != null) {
                    result.append(",\"error\":\"").append(event.error()).append("\"");
                }
                result.append("}");
            }
        }
        return result.append("]").toString();
    }

    private static void respond(HttpExchange exchange, int status, byte[] body,
                                String type, String etag) throws java.io.IOException {
        if (type != null) exchange.getResponseHeaders().set("Content-Type", type);
        if (etag != null) exchange.getResponseHeaders().set("ETag", etag);
        if (status == 200 && etag != null && body.length > 0) {
            exchange.getResponseHeaders().set("Last-Modified", "Thu, 10 Sep 2026 00:00:00 GMT");
        }
        if (status == 204 || exchange.getRequestMethod().equals("HEAD") || body.length == 0) {
            exchange.getResponseHeaders().set("Content-Length", String.valueOf(body.length));
            exchange.sendResponseHeaders(status, -1);
            return;
        }
        // HttpServer sets Content-Length for fixed bodies. Never pair it with
        // a manual zero length while sending chunked framing.
        exchange.sendResponseHeaders(status, body.length);
        exchange.getResponseBody().write(body);
    }
}
