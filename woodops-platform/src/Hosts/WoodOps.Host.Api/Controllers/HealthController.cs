using Microsoft.AspNetCore.Mvc;

namespace WoodOps.Host.Api.Controllers;

[ApiController]
[Route("health")]
public sealed class HealthController : ControllerBase
{
    [HttpGet]
    public IActionResult Get()
    {
        return Ok(new
        {
            status = "healthy",
            service = "WoodOps.Host.Api"
        });
    }
}