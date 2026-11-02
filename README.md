# autocor-lab

Hands-on lab code and guided exercises for **Cisco 350-901 AUTOCOR v2.0** (CCNP / CCIE Automation core exam), written while preparing for the exam myself. The guides are in German; the code and comments are in English.

| Guide | Blueprint | Needs |
|---|---|---|
| [YANG to JSON and YAML](guides/yang-json-yaml.md) | 2.7 | your computer only |
| [RESTCONF against Arista cEOS](guides/restconf.md) | 1.3 | ContainerLab |
| [Docker Compose inventory stack](guides/docker-compose.md) | 2.5 | ContainerLab, Docker |

Start with [lab setup](guides/lab-setup.md). More guides follow as I work through the blueprint.

- **Read the guides online:** https://autocor.silvancodes.dev/wiki/
- **Practice with the free trainer** (quiz, flash cards, mock exam, progress per topic): https://autocor.silvancodes.dev/

## Layout

```
guides/                 the guided exercises
lab/clab/               ContainerLab topology: 2x Arista cEOS, 1x Nokia SR Linux
lab/restconf/           RESTCONF inventory script
lab/compose/inventory/  finished Compose stack from the guide
lab/yang/               fetch YANG models, pyang and yanglint helpers
```

The Arista cEOS image is not included: download it yourself after a free registration at arista.com. The credentials in `lab/clab/` are the public ContainerLab defaults for throw-away lab nodes. Never reuse them.

## Disclaimer

Unofficial, not affiliated with or endorsed by Cisco or Arista. All content is self-written from the public exam topics and contains no real exam questions.

## License

Code: [MIT](LICENSE). Guides in `guides/`: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
