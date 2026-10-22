import http from 'node:http';
import { deflateSync } from 'node:zlib';
const retryIDs = new Set();
function crc32(buffer) { let crc = -1; for (const byte of buffer) { crc ^= byte; for (let i=0;i<8;i++) crc=(crc>>>1)^((crc&1)?0xedb88320:0); } return (crc^-1)>>>0; }
function chunk(type, data) { const name=Buffer.from(type); const output=Buffer.alloc(data.length+12);output.writeUInt32BE(data.length);name.copy(output,4);data.copy(output,8);output.writeUInt32BE(crc32(Buffer.concat([name,data])),output.length-4);return output; }
const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(4096);ihdr.writeUInt32BE(2048,4);ihdr[8]=8;ihdr[9]=2;
const image=Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',ihdr),chunk('IDAT',deflateSync(Buffer.alloc((4096*3+1)*2048,0))),chunk('IEND',Buffer.alloc(0))]);
const server=http.createServer((request,response)=>{
  const json=(status,value)=>{response.writeHead(status,{'content-type':'application/json'});response.end(JSON.stringify(value));};
  if(request.headers.authorization!=='Bearer native-fixture'){json(401,{error:'unauthorized'});return;}
  if(request.url==='/me/access-status'){json(200,{userId:'native-qa-isolated',accessStatus:{plan:'free',isUnlimited:false,isTrial:false,todayUsed:5,todayLimit:20,dailyResetAt:'2026-10-23T00:00:00.000Z',storage:{usedBytes:50*1024*1024,limitBytes:200*1024*1024,imageLimitBytes:50*1024*1024,fileLimitBytes:0,retentionDays:3,canUploadFiles:false}}});return;}
  if(request.url==='/message-categories'){json(200,{categories:Array.from({length:20},(_,i)=>({id:`category-${i}`,userId:'native-qa-isolated',name:i===0?'收件箱':`项目 ${i}`,color:'sky',isDefault:i===0,sortOrder:i,createdAt:'2026-10-22T00:00:00.000Z',updatedAt:'2026-10-22T00:00:00.000Z'}))});return;}
  if(request.url.startsWith('/messages')&&request.method==='GET'){json(200,{messages:Array.from({length:10000},(_,i)=>({id:`message-${i}`,userId:'native-qa-isolated',type:'text',textContent:`跨端测试消息 ${i} · 支持中文长内容与分类切换。`,categoryId:`category-${i%20}`,categoryName:`项目 ${i%20}`,isCleared:i%4===0,isDeleted:false,createdAt:'2026-10-22T00:00:00.000Z',updatedAt:'2026-10-22T00:00:00.000Z'}))});return;}
  if(request.url==='/me/timezone'){json(200,{ok:true});return;}
  if(request.url==='/api/media/image'){response.writeHead(200,{'content-type':'image/png'});response.end(image);return;}
  if(request.url==='/api/media/expired'){json(410,{error:'attachment_expired'});return;}
  if(request.url==='/api/media/redirect'){response.writeHead(302,{location:'http://127.0.0.1:3001/leak'});response.end();return;}
  if(request.url==='/api/media/slow'){setTimeout(()=>{if(!response.destroyed){response.writeHead(200);response.end('private fixture');}},1000);return;}
  if(request.url==='/api/media/file'){response.writeHead(200);response.end('original fixture attachment');return;}
  if(request.method==='POST' && request.url==='/messages/file'){
    let size=0;let tail=Buffer.alloc(0);
    request.on('data',data=>{size+=data.length;tail=Buffer.concat([tail,data]).subarray(-2048);});
    request.on('end',()=>{
      const declared=Number(request.headers['x-upload-size']);
      if(size<declared || size>declared+4096){json(400,{error:'invalid_upload'});return;}
      const fileName=tail.toString().match(/name="fileName"\r\n\r\n([^\r]+)/)?.[1]??'fixture.txt';
      const uploadID=request.headers['x-upload-id'];
      if(fileName==='retry.txt'&&!retryIDs.has(uploadID)){retryIDs.add(uploadID);json(503,{error:'retry_fixture'});return;}
      const result={id:uploadID,userId:'native-fixture',type:'file',fileName,fileSize:declared,isCleared:false,isDeleted:false,createdAt:'2026-10-22T00:00:00.000Z',updatedAt:'2026-10-22T00:00:00.000Z'};
      if(fileName==='slow.txt')setTimeout(()=>{if(!response.destroyed)json(201,result);},1500);else json(201,result);
    });return;
  }
  json(404,{error:'not_found'});
});
server.listen(3000,'127.0.0.1',()=>console.log('Native fixture ready'));
