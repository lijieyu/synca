import { Router, type Request, type RequestHandler } from 'express';
import { z } from 'zod';
import { getUserIdFromToken } from './auth.js';
import { LoginError, getLoginMethods, requestEmailCode, verifyEmailCode, requestAppleBinding, bindAppleIdentity, type BindingActor } from './emailAuth.js';
const emailBody=z.object({email:z.string().min(1).max(254),locale:z.string().max(20).optional()});
const codeBody=z.object({challengeId:z.string().regex(/^[a-f0-9]{64}$/),code:z.string().regex(/^\d{6}$/),deviceId:z.string().max(200).optional()});
async function actor(req:Request):Promise<BindingActor>{
 const token=req.header('Authorization')?.replace(/^Bearer /,'') ?? '';
 const userId=await getUserIdFromToken(req.header('Authorization'));
 if(!userId)throw new LoginError('unauthorized',401);
 return {userId,sessionToken:token};
}
const wrap=(handler:(req:Request)=>Promise<unknown>):RequestHandler=>async(req,res,next)=>{
 res.setHeader('Cache-Control','no-store');
 try{res.json(await handler(req));}catch(e){
  if(e instanceof z.ZodError){res.status(400).json({error:'invalid_payload'});return;}
  if(e instanceof LoginError){if(e.retryAfter)res.setHeader('Retry-After',String(e.retryAfter));res.status(e.status).json({error:e.code,...(e.retryAfter?{retryAfter:e.retryAfter}:{})});return;}
  next(e);
 }
};
export function createEmailAuthRouter(){
 const router=Router();
 // This deployment's nginx connects locally. Do not trust caller-supplied XFF
 // on a directly reachable backend port, even though legacy routes trust one hop.
 const ip=(req:Request)=>{
  const peer=req.socket.remoteAddress ?? 'unknown';
  return ['127.0.0.1','::1','::ffff:127.0.0.1'].includes(peer) ? req.ip ?? peer : peer;
 };
 router.post('/auth/email/code',wrap(async req=>requestEmailCode({...emailBody.parse(req.body),ip:ip(req)})));
 router.post('/auth/email/verify',wrap(async req=>verifyEmailCode({...codeBody.parse(req.body),ip:ip(req)})));
 router.get('/me/login-methods',wrap(async req=>getLoginMethods((await actor(req)).userId)));
 router.post('/me/login-methods/email/code',wrap(async req=>requestEmailCode({...emailBody.parse(req.body),ip:ip(req),actor:await actor(req)})));
 router.post('/me/login-methods/email/verify',wrap(async req=>verifyEmailCode({...codeBody.parse(req.body),ip:ip(req),actor:await actor(req)})));
 router.post('/me/login-methods/apple/challenge',wrap(async req=>requestAppleBinding(await actor(req))));
 router.post('/me/login-methods/apple',wrap(async req=>bindAppleIdentity(await actor(req),z.object({challengeId:z.string().regex(/^[a-f0-9]{64}$/),idToken:z.string().min(1).max(16384)}).parse(req.body),ip(req))));
 return router;
}
