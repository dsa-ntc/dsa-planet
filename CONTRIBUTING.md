# Guidelines and Instructions for Contributing

## Manually adding your feed via Pull Request

If you don't want to wait for a member of the NTC to add your feed,
you can bypass the issues template to add it directly to the file
[planet.ini](planet.ini).

1. Fork this repository
2. Upload your avatar to [hackergotchi directory](hackergotchi)
  * Supported formats: `jpg`, `png`, (some) `svg` files, and `webp`. When in doubt, just use your chapter's Twitter or Facebook avatar. Webp is preferred as it speeds up load times.
3. Edit [planet.ini](planet.ini) and add a new section containing the info for your feed

  ```ini
  [exampledsa]
  title = Example DSA
  feed = https://www.example.com/feed/
  link = https://www.example.com
  location = en
  avatar = example.webp
  ```

4. Open a Pull Request against this repository.

Alternatively you can send an email to 
[ntc@dsacommittees.org](mailto:ntc@dsacommittees.org?subject=%5Bdsa-feed%5D%20&body=I%20have%20a%20question%20about%20DSA%20Feed)
with all the mandatory information listed above

## Development environment

### Jekyll development

To run this website locally, use the following commands:

```sh
git clone https://github.com/dsa-ntc/dsa-planet # substitute in your fork url if you're using your fork
cd dsa-planet
bundle config set --local path 'vendor/bundle'
bundler install
bundler exec rake build
bundler exec jekyll serve
```
and visit [127.0.0.1:4000](http://127.0.0.1:4000)

### Feed test development
To test the feeds and avatars found in planet.ini, use the following commands:

```sh
git clone https://github.com/dsa-ntc/dsa-planet # substitute in your fork url if you're using your fork
cd dsa-planet
bundle config set --local path 'vendor/bundle'
bundler install
bundle exec ruby tests/feedcheck.rb
```
