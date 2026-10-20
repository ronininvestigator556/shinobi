# No Tor in Shinobi

The prior tool supported Tor via a local daemon. Shinobi deliberately **drops Tor** — "leave Tor for Tor." Shinobi is for anonymized collection of legally public, clearnet information; the dark web is a separate domain with its own tooling, threat model, and legal considerations. Shinobi routes through operator-supplied proxies only.

Recorded because anyone familiar with the prior tool will wonder why Tor was removed; this is a scope decision, not an oversight.
