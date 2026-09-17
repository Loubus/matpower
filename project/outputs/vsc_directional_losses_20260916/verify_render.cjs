const {chromium}=require('C:/Users/Santiago/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),{pathToFileURL}=require('url');
(async()=>{
 const out=__dirname, dest=path.join(out,'verification');fs.mkdirSync(dest,{recursive:true});
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 const page=await browser.newPage({viewport:{width:1280,height:1000}});let errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.goto(pathToFileURL(path.join(out,'REPORT.html')).href);
 const desktop=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,
  svg:document.querySelectorAll('svg').length,images:[...document.images].every(x=>x.complete&&x.naturalWidth>0),
  rawMath:/\\(?:frac|le|ne|quad)/.test(document.body.innerText)}));
 await page.screenshot({path:path.join(dest,'cover.png')});
 await page.locator('.table').first().screenshot({path:path.join(dest,'parameters.png')});
 for(let i=0;i<await page.locator('.equation').count();i++)await page.locator('.equation').nth(i).screenshot({path:path.join(dest,'equation-'+i+'.png')});
 await page.locator('figure').screenshot({path:path.join(dest,'capability.png')});
 const links=await page.locator('a').evaluateAll(as=>as.map(a=>a.getAttribute('href')));
 const missing=links.filter(x=>!/^https?:/.test(x)&&!fs.existsSync(path.resolve(out,x.split('#')[0])));
 await page.setViewportSize({width:390,height:844}); await page.evaluate(()=>scrollTo(0,0));
 const mobile=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth}));
 await page.screenshot({path:path.join(dest,'mobile.png')});
 const result={desktop,mobile,missing_links:missing,errors,passed:!errors.length&&!missing.length&&desktop.images&&!desktop.rawMath&&desktop.width===desktop.scroll&&mobile.width===mobile.scroll};
 fs.writeFileSync(path.join(dest,'render.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));await browser.close();
})();
