# Redacts obvious secrets from text that is copied into the handoff file.
def scrub:
  gsub("-----BEGIN[A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END[A-Z ]*PRIVATE KEY-----"; "[redacted private key]")
  | gsub("eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}"; "[redacted jwt]")
  | gsub("sk-(ant-)?[A-Za-z0-9_-]{16,}"; "[redacted key]")
  | gsub("AKIA[0-9A-Z]{16}"; "[redacted aws key]")
  | gsub("gh[pousr]_[A-Za-z0-9]{30,}"; "[redacted github token]")
  | gsub("xox[abprs]-[A-Za-z0-9-]{10,}"; "[redacted slack token]")
  | gsub("(?<k>(?i)bearer\\s+)[A-Za-z0-9._~+/=-]{16,}"; "\(.k)[redacted]")
  | gsub("(?<k>(?i)(api[_-]?key|secret|token|password|passwd|authorization)\\s*[:=]\\s*)[^\\s\"']{6,}"; "\(.k)[redacted]");
