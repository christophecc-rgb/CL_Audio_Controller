document.getElementById('verify').onclick=async()=>{
  const result=document.getElementById('result');
  try{
    const response=await fetch('/remote/verify',{method:'POST'});const data=await response.json();
    if(!response.ok)throw new Error(data.error);
    result.textContent=data.message;
  }catch(error){result.textContent=error.message;}
};
