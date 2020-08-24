# Refactor Rails 3.2.22.4 controller

Please refactor `app/controllers/gigs/inquiries_controller.rb` as you like and
explain your changes.

Further domain knowledge:

- a gigmit User can have many Profiles
- Promoter and Artist are both Profiles
- a Promoter has many Gigs (aka a call for applications)
- an Artist applies to Gigs through an Inquiry
- a Rider is a document attached to an Artist and to an Inquiry

Result:

- diff file of refactored and original code
- description/briefing/log of your refactoring approach
