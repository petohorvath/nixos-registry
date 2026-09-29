{ example }:
{
  testStaticNixosExampleEvaluatesAndValidates = {
    expr = example.result;
    expected = {
      central = {
        domain = "example.test";
        services = { };
      };
      combined = {
        domain = "example.test";
        services.metrics = {
          host = "monitor.example.test";
          port = 9191;
          endpoint = "monitor.example.test:9191";
        };
      };
      endpoint = "monitor.example.test:9191";
      validate = true;
    };
  };
}
