# WooF.Play через TestFlight

TestFlight — рекомендуемый способ дать другим людям устанавливать WooF.Play без подключения телефона к вашему Mac. Для TestFlight не требуется Developer Mode, регистрация UDID или development‑IPA.

## Что требуется

1. Активная платная подписка **Apple Developer Program**.
2. Доступ к **App Store Connect** с ролью Account Holder, Admin или App Manager.
3. Запись приложения в App Store Connect с bundle ID `app.kinopad.KinoPad`.
4. Уникальный номер сборки для каждой загрузки.

Текущий локальный профиль Personal Team действует 7 дней и не подходит для TestFlight. После активации программы Xcode сможет создать distribution‑сертификат и App Store provisioning profile автоматически.

## Первая публикация

1. Создайте приложение в App Store Connect и выберите bundle ID `app.kinopad.KinoPad`.
2. В Xcode откройте `KinoPad.xcodeproj`, выберите платную Team в **Signing & Capabilities**.
3. Выполните `./scripts/build-testflight-archive.sh` или в Xcode выберите **Product → Archive**.
4. В **Window → Organizer → Archives** выберите архив, затем **Distribute App → App Store Connect → Upload**.
5. После обработки сборки заполните **TestFlight → Test Information** и добавьте группу тестировщиков.
6. Для внешних пользователей создайте публичную ссылку. Первая внешняя сборка проходит Beta App Review.

Внутренних тестировщиков может быть до 100, внешних — до 10 000. Каждая сборка TestFlight доступна 90 дней.

## Обновления через Git

Безопасный автоматический вариант — **Xcode Cloud**:

1. подключите GitHub‑репозиторий в Xcode Cloud;
2. создайте workflow на изменения ветки `main`;
3. добавьте действие Archive для iOS;
4. включите распространение успешной сборки в нужную TestFlight‑группу.

Так сертификаты и ключи остаются у Apple. Если позже будет использоваться GitHub Actions, храните App Store Connect API key (`.p8`), Key ID и Issuer ID только в GitHub Secrets. Никогда не добавляйте их в репозиторий.
