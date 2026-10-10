const {chromium}=require('playwright');
const fs=require('fs');
(async()=>{
 const link=fs.readFileSync('.build/phone-test-link.txt','utf8');
 const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
 try {
  const page=await browser.newPage({viewport:{width:390,height:844}});
  const errors=[]; page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{window.patterns=[];Object.defineProperty(navigator,'vibrate',{value:p=>{window.patterns.push(p);return true;}});});
  await page.goto(link); await page.getByRole('button',{name:'Enable vibration',exact:true}).click();
  await page.waitForFunction(()=>window.patterns.some(p=>JSON.stringify(p)==='[180,180,540]'));
  await page.waitForFunction(()=>window.patterns.includes(0)||window.patterns.some(p=>JSON.stringify(p)==='[0]'));
  await page.screenshot({path:'verification/android-receiver.png',fullPage:true});
  const denied=await fetch(new URL('/events?token=wrong',link)); if(denied.status!==403)throw Error('Unauthorized request accepted');
  const good=await fetch(new URL('/ready'+new URL(link).search,link)); if(good.status!==200)throw Error('Ready endpoint failed');
  await page.getByRole('button',{name:'Stop & disconnect'}).click();
  await page.waitForFunction(()=>document.getElementById('status').textContent.startsWith('Stopped'));
  if(errors.length)throw Error(errors.join('\n'));
  const patterns=await page.evaluate(()=>window.patterns);
  if(!patterns.some(p=>JSON.stringify(p)==='[100,120,100]'))throw Error('Output activation cue missing');
  console.log(JSON.stringify({pass:true,phonePage:true,enable:true,receivedMorsePattern:true,receivedStop:true,deniedWrongToken:true,stopButton:true,browserErrors:errors.length,physicalVibration:'not tested; navigator.vibrate mocked'}));
 } finally {fs.writeFileSync('.build/phone-test-finished','done');await browser.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
