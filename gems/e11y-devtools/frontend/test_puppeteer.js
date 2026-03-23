import puppeteer from 'puppeteer';

(async () => {
  const browser = await puppeteer.launch({ headless: "new" });
  const page = await browser.newPage();
  
  page.on('console', msg => console.log('PAGE LOG:', msg.text()));
  
  await page.goto('http://localhost:5173');
  await page.waitForSelector('.e11y-fab', { timeout: 5000 });
  await page.click('.e11y-fab');
  await page.waitForSelector('.e11y-histo-chart-host', { timeout: 5000 });
  
  await page.evaluate(() => {
    const host = document.querySelector('.e11y-histo-brush-overlay');
    if (host) {
      const rect = host.getBoundingClientRect();
      const down = new PointerEvent('pointerdown', { clientX: rect.left + 50, clientY: rect.top + 20, button: 0, bubbles: true });
      host.dispatchEvent(down);
      
      const move = new PointerEvent('pointermove', { clientX: rect.left + 150, clientY: rect.top + 20, button: 0, bubbles: true });
      host.dispatchEvent(move);
      
      const up = new PointerEvent('pointerup', { clientX: rect.left + 150, clientY: rect.top + 20, button: 0, bubbles: true });
      host.dispatchEvent(up);
    }
  });
  
  await new Promise(r => setTimeout(r, 500));
  
  await page.evaluate(() => {
    const shade = document.querySelector('.e11y-histo-sel-shade');
    if (shade) {
      console.log('SHADE AFTER FAKE EVENT:', shade.style.left, shade.style.width);
    } else {
      console.log('SHADE AFTER FAKE EVENT: null');
    }
  });
  
  await browser.close();
})();
