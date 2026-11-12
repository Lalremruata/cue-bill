// Live pool-table clock used by the Tables & Orders page (Alpine: x-data="cbClock({...})").
window.cbClock = function (c) {
    const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 });
    const offset = c.serverNow - Date.now(); // keeps tablets on the LAN in sync with the counter PC

    return {
        now: Date.now() + offset,
        init() {
            this.timer = setInterval(() => { this.now = Date.now() + offset; }, 1000);
        },
        destroy() { clearInterval(this.timer); },
        get elapsed() {
            if (!c.start) return 0;
            const end = c.stoppedAt || c.pausedAt || this.now;
            return Math.max(0, Math.floor((end - c.start) / 1000) - c.pausedSeconds);
        },
        get clock() {
            const s = this.elapsed, p = (n) => String(n).padStart(2, '0');
            return p(Math.floor(s / 3600)) + ':' + p(Math.floor(s / 60) % 60) + ':' + p(s % 60);
        },
        get billedMinutes() {
            if (this.elapsed <= 0) return 0;
            let m = Math.ceil(this.elapsed / 60);
            if (c.block > 1) m = Math.ceil(m / c.block) * c.block;
            return Math.max(m, c.min);
        },
        get poolAmount() { return Math.round(this.billedMinutes / 60 * c.rate * 100) / 100; },
        get total() {
            return this.poolAmount * (1 + c.gstPool / 100) + c.items * (1 + c.gstFood / 100);
        },
        money(v) { return inr.format(Math.round(v)); },
    };
};
