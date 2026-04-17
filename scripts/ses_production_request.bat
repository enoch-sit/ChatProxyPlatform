@echo off
aws sesv2 put-account-details --mail-type TRANSACTIONAL --website-url "https://aidcec-ai-agent.com" --use-case-description "AI chatbot platform for internal org demo. Sends password reset and account verification emails to registered users only. Low volume, transactional emails." --additional-contact-email-addresses "aai002@eduhk.hk" --production-access-enabled --region us-east-1
echo Done.
