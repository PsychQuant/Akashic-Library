// #124 verify F1/F5/Codex-1/2：以「字母序最先的 activation 測試」啟用守衛，
// 在 --filter（activation 沒被選中）與 --parallel（每個 test case 一個
// process，activation process 裡沒有別的測試）下**靜默零保護**。
// C constructor 在 bundle 被載入時就跑——每個 worker process、任何 filter
// 組合都涵蓋，且早於 XCTest 的任何排程。
extern void akashic_test_guard_activate(void);

__attribute__((constructor)) static void akashic_test_guard_bootstrap(void) {
    akashic_test_guard_activate();
}

void akashic_test_guard_loader_touch(void) {}
